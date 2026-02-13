#!/usr/bin/env ruby
require "debug"
require "obsws"
require "awesome_print"

class Main
    def run
        OBSWS::Requests::Client
            .new(host: "localhost", port:4455)
            .run do |client|
                # resp = client.get_version
                # puts resp.attrs
                puts client.get_version.available_requests
                ap client.get_version
                binding.break
            end
    end
end


Main.new.run if $PROGRAM_NAME == __FILE__
