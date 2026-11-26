# frozen_string_literal: true

require "json"
require "digest"

module Stardew
  module Dsl
    class Error < ArgumentError; end

    SEASONS = %i[spring summer fall winter].freeze
    TYPES = %i[acquire reserve deliver harvest plant reach unlock talk gift complete build earn maintain].freeze
    PRIORITIES = %i[critical high normal low].freeze
    CONSTRAINTS = %i[preserve_bundle_items respect_energy_budget respect_travel_time respect_inventory_capacity avoid_unnecessary_passouts no_hidden_rng].freeze

    def self.canonical(value)
      case value
      when Hash
        value.transform_keys(&:to_s).sort.to_h.transform_values { |v| canonical(v) }.freeze
      when Array
        value.map { |v| canonical(v) }.freeze
      when Symbol
        value.to_s.freeze
      when String
        value.dup.freeze
      when Integer, TrueClass, FalseClass, NilClass
        value
      else
        raise Error, "unsupported value: #{value.class}"
      end
    end

    def self.id(value)
      raise Error, "invalid identifier: #{value.inspect}" unless value.is_a?(Symbol) && /\A[a-z][a-z0-9_]*\z/.match?(value.to_s)

      value
    end

    def self.positive(value)
      raise Error, "expected positive integer" unless value.is_a?(Integer) && value.positive?

      value
    end

    def self.date(season, day, year = 1)
      raise Error, "invalid season/day" unless SEASONS.include?(season) && day.is_a?(Integer) && (1..28).cover?(day)

      positive(year)
      { year: year, season: season, day: day }
    end

    def self.ordinal(date)
      raise Error, "invalid date" unless date.is_a?(Hash)

      checked = self.date(date.fetch(:season), date.fetch(:day), date.fetch(:year))
      (checked[:year] - 1) * 112 + SEASONS.index(checked[:season]) * 28 + checked[:day]
    rescue KeyError
      raise Error, "invalid date"
    end

    class Builder
      SEASONS.each do |season|
        define_method(season) { |day, year: 1| Dsl.date(season, day, year) }
      end

      private

      def set(key, value)
        raise Error, "duplicate directive: #{key}" if @data.key?(key)

        @data[key] = value
      end
    end

    class Goal < Builder
      attr_reader :data

      def initialize(id, recurring: false)
        @data = { id: Dsl.id(id), recurring: recurring, requires: [], strategies: [], routes: [] }
      end

      def target(type, subject, quantity: 1, quality: nil, **options)
        raise Error, "unknown goal type: #{type}" unless TYPES.include?(type)

        set(:target, { type: type, subject: subject, quantity: Dsl.positive(quantity), quality: quality, options: options })
      end

      def requires(*ids)
        @data[:requires].concat(ids.map { |id| Dsl.id(id) })
      end

      def strategy(id)
        @data[:strategies] << Dsl.id(id)
      end

      def prefer_by(date)
        set(:prefer_by, date)
      end

      def deadline(date)
        set(:deadline, date)
      end

      def priority(value)
        raise Error, "unknown priority" unless PRIORITIES.include?(value)

        set(:priority, value)
      end

      def when_needed(subject)
        set(:when_needed, Dsl.id(subject))
      end

      def every(*days)
        raise Error, "invalid recurrence" if days.empty? || (days - %i[day monday tuesday wednesday thursday friday saturday sunday]).any?
        raise Error, "recurrence requires recurring goal" unless @data[:recurring]

        set(:every, days.uniq)
      end

      def route(action, **parameters)
        @data[:routes] << { action: Dsl.id(action), parameters: parameters }
      end

      def finish
        raise Error, "missing target: #{@data[:id]}" unless @data.key?(:target)
        raise Error, "missing recurrence: #{@data[:id]}" if @data[:recurring] && !@data.key?(:every)
        %i[prefer_by deadline].each { |key| Dsl.ordinal(@data[key]) if @data.key?(key) }
        if @data[:prefer_by] && @data[:deadline] && Dsl.ordinal(@data[:prefer_by]) > Dsl.ordinal(@data[:deadline])
          raise Error, "preferred date after deadline: #{@data[:id]}"
        end

        @data
      end
    end

    class GoalSet < Builder
      attr_reader :goals

      def initialize
        @goals = {}
      end

      def goal(id, &block)
        add(id, false, &block)
      end

      def recurring(id, &block)
        add(id, true, &block)
      end

      private

      def add(id, recurring, &block)
        raise Error, "duplicate goal: #{id}" if @goals.key?(id)

        builder = Goal.new(id, recurring: recurring)
        builder.instance_eval(&block)
        @goals[id] = builder.finish
      end
    end

    class Run < Builder
      attr_reader :data

      def initialize(id)
        @data = { id: Dsl.id(id), goal_sets: [], objectives: {}, constraints: [], required: [] }
      end

      def title(value)
        set(:title, String(value))
      end

      def starts(date)
        set(:starts, date)
      end

      def finishes(date)
        set(:finishes, date)
      end

      def include_goals(*ids)
        @data[:goal_sets].concat(ids.map { |id| Dsl.id(id) })
      end

      def require_completion(*ids)
        @data[:required].concat(ids.map { |id| Dsl.id(id) })
      end

      def optimize(id, weight:)
        Dsl.id(id)
        raise Error, "duplicate objective: #{id}" if @data[:objectives].key?(id)

        @data[:objectives][id] = Dsl.positive(weight)
      end

      def constraints(*ids)
        raise Error, "unknown constraint" unless (ids - CONSTRAINTS).empty?

        @data[:constraints].concat(ids)
      end
    end

    class Compiler
      def initialize(ruleset:)
        @ruleset = String(ruleset)
        raise Error, "missing ruleset" if @ruleset.empty?

        @sets = {}
        @runs = {}
      end

      def goal_set(id, &block)
        Dsl.id(id)
        raise Error, "duplicate goal set: #{id}" if @sets.key?(id)

        builder = GoalSet.new
        builder.instance_eval(&block)
        @sets[id] = builder.goals
      end

      def run(id, &block)
        raise Error, "duplicate run: #{id}" if @runs.key?(id)

        builder = Run.new(id)
        builder.instance_eval(&block)
        @runs[id] = builder.data
      end

      def load_file(path)
        instance_eval(File.read(path), path.to_s, 1)
        self
      end

      def compile(id)
        run = @runs.fetch(id) { raise Error, "unknown run: #{id}" }
        first = Dsl.ordinal(run[:starts])
        last = Dsl.ordinal(run[:finishes])
        raise Error, "run ends before it starts" if first > last
        raise Error, "duplicate goal set inclusion" unless run[:goal_sets].uniq == run[:goal_sets]

        goals = {}
        run[:goal_sets].each do |name|
          @sets.fetch(name) { raise Error, "unknown goal set: #{name}" }.each do |key, goal|
            raise Error, "duplicate goal: #{key}" if goals.key?(key)

            goals[key] = goal
          end
        end
        (run[:required] + goals.values.flat_map { |goal| goal[:requires] }).each do |key|
          raise Error, "unknown goal reference: #{key}" unless goals.key?(key)
        end
        goals.each_value do |goal|
          %i[prefer_by deadline].each do |key|
            next unless goal[key]
            raise Error, "goal date outside run: #{goal[:id]}" unless (first..last).cover?(Dsl.ordinal(goal[key]))
          end
        end
        check_cycles(goals)
        Dsl.canonical(schema_version: 1, ruleset: @ruleset, run: run, goals: goals)
      end

      def self.json(ir)
        JSON.generate(ir)
      end

      def self.digest(ir)
        Digest::SHA256.hexdigest(json(ir))
      end

      private

      def check_cycles(goals)
        visiting = {}
        visited = {}
        visit = lambda do |id|
          raise Error, "dependency cycle at #{id}" if visiting[id]
          return if visited[id]

          visiting[id] = true
          goals.fetch(id)[:requires].each { |dep| visit.call(dep) }
          visiting.delete(id)
          visited[id] = true
        end
        goals.each_key { |id| visit.call(id) }
      end
    end
  end
end
