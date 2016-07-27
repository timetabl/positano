require_relative 'sql_generator'
require_relative 'ewha'
require_relative 'sogang'
require_relative 'yonsei'

module CLI
  module_function

  def univ_module
    if ARGV.size < 2
      $stderr.puts "usage: ruby #{$0} (ewha|sogang|yonsei|wonju) YEAR_TERM"
      exit 1
    end

    semester = Semester.new ARGV[1][0..3].to_i, ARGV[1][4].to_i
    case ARGV[0]
    when 'ewha'
      Ewha::Web.new semester
    when 'sogang'
      Sogang::Web.new semester
    when 'yonsei'
      Yonsei::Web.new 's1', semester
    when 'wonju'
      Yonsei::Web.new 's2', semester
    else
      $stderr.puts "usage: ruby #{$0} (ewha|sogang|yonsei|wonju) YEAR_TERM"
      exit 1
    end
  end

  def run
    SQLGenerator.generate univ_module, $stdout
  rescue Interrupt
    puts "Interrupted."
  end
end
