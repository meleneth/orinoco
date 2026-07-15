# frozen_string_literal: true

class Admin::EventPipelineController < ApplicationController
  def index
    @queues = queue_inspector.queues
  rescue StandardError => e
    @queues = []
    @error = e
  end

  def clear
    queue = queue_inspector.queue(params[:id])
    raise ActiveRecord::RecordNotFound, "unknown queue #{params[:id]}" unless queue

    queue_inspector.clear(params[:id])
    redirect_to admin_event_pipeline_path, notice: "Cleared #{params[:id]}"
  rescue StandardError => e
    redirect_to admin_event_pipeline_path, alert: "Could not clear #{params[:id]}: #{e.class}: #{e.message}"
  end
  def show
    @queue = queue_inspector.queue(params[:id])
    raise ActiveRecord::RecordNotFound, "unknown queue #{params[:id]}" unless @queue

    @messages = queue_inspector.peek(params[:id])
  rescue StandardError => e
    @messages = []
    @error = e
  end

  private

  def queue_inspector
    @queue_inspector ||= Orinoco::Messaging::QueueInspector.new(
      sqs: sqs,
      topology: topology
    )
  end

  def sqs
    @sqs ||= Aws::SQS::Client.new(**app_config.event_pipeline.aws_client_options)
  end

  def topology
    app_config.orinoco.messaging_topology
  end

  def app_config
    Rails.configuration.x
  end
end
