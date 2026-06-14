# frozen_string_literal: true

module SuppressOutput
  def suppress_output
    original_stdout = $stdout
    original_stderr = $stderr
    null_io = File.open(File::NULL, "w")

    $stdout = null_io
    $stderr = null_io

    yield
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
    null_io.close unless null_io.closed?
  end
end

RSpec.configure do |config|
  config.include SuppressOutput
end
