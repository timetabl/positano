require 'fileutils'
require 'oj'

module Cache
  module_function

  DIR = File.join __dir__, 'cache'
  FileUtils.mkdir_p DIR

  def key_to_filename(key)
    key.tr '/', '–'
  end

  def try(key)
    filename = File.join DIR, key_to_filename(key)
    begin
      IO.read filename, mode: 'rt:utf-8'
    rescue Errno::ENOENT
      warn "cache miss [#{key}]"
      data = yield
      IO.write filename, data, mode: 'wt:utf-8'
      data
    end
  end

  def try_json(key)
    Oj.load try("#{key_to_filename(key)}.json") {
      Oj.dump yield
    }
  end
end
