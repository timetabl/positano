require 'set'
require 'selenium-webdriver'
require 'nokogiri'
require_relative 'cache'

# http://ysweb.yonsei.ac.kr:8888/curri120601/curri_new.jsp#top

module Yonsei
  class Web
    KEYS = Selenium::WebDriver::Keys
    Select = Selenium::WebDriver::Support::Select

    UNIV_MAP = Hash[*%w[ s1 yonsei s2 wonju ]]

    def initialize(branch, semester)
      unless UNIV_MAP[branch]
        raise ArgumentError, "unknown branch <#{branch}>", caller
      end
      @branch = branch

      @id = branch == 's1' ? 2 : 3

      @univ_name = UNIV_MAP[branch]

      @semester = semester

      @conn = Faraday.new url: 'http://ysweb.yonsei.ac.kr:8888' do |faraday|
        faraday.request :url_encoded
        faraday.adapter Faraday.default_adapter
      end
    end

    attr_reader :id, :semester

    class Lesson < ::Lesson
      def t2p time
        p = (time.to_i - 480) / 60
        raise RangeError, "out of range: #{p}", caller unless (0..15).include? p
        p
      end
    end

    def web_driver
      @web_driver ||= begin
        web_driver = Selenium::WebDriver.for :firefox
        web_driver.get 'http://ysweb.yonsei.ac.kr:8888/curri120601/curri_new.jsp#top'
        web_driver
      end
    end

    def choose_HY
      elem = web_driver.find_element id: 'HY'
      elem.send_keys KEYS[:end]
      select = Select.new elem
      last_selected_text = nil
      while last_selected_text != select.first_selected_option.text && select.first_selected_option.text > @semester.year.to_s
        elem.send_keys KEYS[:up]
        last_selected_text = select.first_selected_option.text
      end
      if select.first_selected_option.text != @semester.year.to_s
        raise 'no such semester'
      end
      elem.send_keys KEYS[:enter]
      sleep 2
    end
    
    def choose_HG
      elem = web_driver.find_element id: 'HG'
      elem.send_keys KEYS[:home]
      elem.send_keys KEYS[:down] if @semester.term == 2
      elem.send_keys KEYS[:enter]
      sleep 2
    end

    def choose_OCODE0(branch)
      if branch == 's2'
        elem = web_driver.find_element id: 'OCODE0'
        elem.send_keys KEYS[:down], KEYS[:enter] 
      end
    end

    def each_OCODE1
      elem = web_driver.find_element id: 'OCODE1'
      select = Select.new elem
      visited = Set.new
      loop do
        # value = elem['value']
        value = select.first_selected_option.text
        break if visited.include? value
        yield value
        visited.add value
        elem.send_keys KEYS[:down], KEYS[:enter]
        sleep 3
      end
    end

    def each_S2
      elem = web_driver.find_element id: 'S2'
      select = Select.new elem
      visited = Set.new
      loop do
        # value = elem['value']
        value = select.first_selected_option.text
        break if visited.include? value
        yield value
        visited.add value
        elem.send_keys KEYS[:down]
      end
    end

    def do_search
      web_driver.execute_script "searchGb('search',1)"
      sleep 1
      wait_loading
    end

    def nbsp_to_sp(text)
      text.gsub "\u00a0", ' '
    end

    def fetch_rows
      js = "return document.getElementById('contenttablejqxgrid').innerHTML"
      html = web_driver.execute_script js
      Nokogiri::HTML(html).css('[role=row]').map { |row|
        row.css('[role=gridcell]').map(&:text).map! { |e| nbsp_to_sp(e).strip }
      }.reject { |e| e.all?(&:empty?) || e[4] == 'No data to display' }
    end

    def next_page?
      elem = web_driver.find_element id: 'pager'
      elem.text !~ /\A\d+-(\d+) of \1\z/
    end

    def move_to_next_page
      elem = web_driver.find_element css: '#pager .jqx-icon-arrow-right'
      elem.click
    end

    def request_data_agent(query = '', form = nil, headers = {})
      url = "/DataAgent?pgm=/curri120601/curri_Data&#{query}"

      request_headers = {
        'Origin' => 'http://ysweb.yonsei.ac.kr:8888',
        'User-Agent' => 'Mozilla/5.0 (Windows NT 6.3; WOW64) AppleWebKit/537.36' \
                        ' (KHTML, like Gecko) Chrome/31.0.1650.63 Safari/537.36',
        'Referer' => 'http://ysweb.yonsei.ac.kr:8888/curri120601/curri_new.jsp',
      }.merge headers

      res = if form
              @conn.post url, form, request_headers
            else
              @conn.get url, request_headers
            end

      raise "status code <#{res.status}>" if res.status != 200

      res.body.encode Encoding::UTF_8, Encoding::CP949
    end

    def download_colleges(branch)
      Cache.try "yonsei-#{branch}-colleges" do
        request_data_agent '', {
          'DmlGb' => 'get_ocode1',
          'ocode0' => branch,
          'lang' => '0',
        }
      end
    end

    def download_domains(key)
      Cache.try "yonsei-domains-#{key}" do
        request_data_agent '', {
          'DmlGb' => 'get_ocode2',
          'ocode1' => key,
          'lang' => '0',
        }
      end
    end

    def download_lectures(branch, college_key, domain_key)
      Cache.try "yonsei-#{branch}-lectures-#{college_key}-#{domain_key}" do
        query = "DmlGb=get_list&ocode0=#{branch}&ocode1=#{college_key}" \
                "&s2=#{domain_key}&hy=#{@semester.year}&hg=#{@semester.term}" \
                "&lang=0&filterscount=0&groupscount=0&pagenum=0&pagesize=15" \
                "&recordstartindex=0&recordendindex=25.84&_=#{Time.now.strftime('%s%L')}"
        request_data_agent query, nil, 'X-Requested-With' => 'XMLHttpRequest'
      end
    end

    SYMBOL_TABLE = Hash[*%w[
      ⓐ 원어강의
      ① 동영상강의
      ② 영어강의
      ⓑ P.NP평가
      ⓒ 국제캠퍼스
    ]]

    def translate_symbols(text)
      SYMBOL_TABLE.reduce text do |r, (k, v)|
        r.gsub k, v + ' '
      end
    end

    def year_mask(text)
      text.scan(/\d+/).map { |e| 1 << e.to_i }.reduce(0, &:|) >> 1 & 0x3f
    end

    DAYNAME = Hash['월화수목금토일'.each_char.zip(1..7)]

    def parse_time_location_pairs(time_str, location_str)
      a = time_str.split('/').reject(&:empty?)
      b = location_str.split('/').reject(&:empty?)
      if b.size == 1 && b !~ /\(|\)/
        return [ a, b * a.size ].transpose
      end
      if a.last =~ /\(([^()]*(?:\([^()]*\))?)\)\z/
        a[-1..-1] = [ $`, $1 ]
        raise unless b.last =~ /\(([^()]*(?:\([^()]*\))?)\)\z/
        b[-1..-1] = [ $`, $1 ]
        if a[-2] =~ /\(([^()]*(?:\([^()]*\))?)\z/
          a[-2..-2] = [ $`, $1 ]
          raise unless b[-2] =~ /\(([^()]*(?:\([^()]*\))?)\z/
          b[-2..-2] = [ $`, $1 ]
        end
      end
      if a.size > 1 && b.size == 1
        b *= a.size
      elsif b.size == 0
        b = [ '' ] * a.size
      end
      [ a, b ].transpose
    end

    def parse_lessons(timestr, locationstr)
      lessons = []
      pairs = parse_time_location_pairs(timestr, locationstr)
      pairs.each do |timestr, locationstr|
        state = 0
        days = []
        timestr.scan(/(월|화|수|목|금|토|일)|(\d+)/) do |m|
          if m[0]
            days.clear if state == 2
            days.push DAYNAME[m[0]]
            state = 1
          else
            days.each do |day|
              lesson = Lesson.new
              lesson.day = day
              lesson.time = m[1].to_i * 60 + 480
              dup_lesson = lessons.find { |e| e.day == lesson.day && e.time == lesson.time }
              if dup_lesson
                dup_lesson.location += "/#{locationstr}"
              else
                lesson.period = 60
                lesson.location = locationstr
                lessons.push lesson
              end
            end
            state = 2
          end
        end
      end
      lessons
    end

    def build_lecture(domain_name, data)
      # ? ? ? 학년 종별
      # 단위 학정번호-분반(-실습) 학점 교과목명 ?
      # ? ? ? 담당교수 강의시간
      # 강의실 유의사항
      closed = data[16].include? '폐강'
      lecture = Lecture.new @univ_name, @semester.to_i, data[6]
      lecture.title = data[8]
      lecture.year = year_mask(data[3])
      lecture.domain = domain_name
      lecture.credits = data[7].to_f unless closed
      lecture.lecturer = data[13]
      lecture.remark = [
        data[4],
        data[5],
        translate_symbols(data[16]),
      ].join(' ').strip()
      lecture.lessons.replace parse_lessons data[14], data[15] unless closed
      lecture
    rescue => error
      raise error.class, "parse error (#{data.inspect}) (#{error.message}",
        error.backtrace
    end

    def wait_loading
      elem = web_driver.find_element class: 'jqx-grid-load'
      sleep 1 while elem.displayed?
    end

    def each_row
      choose_HY
      choose_HG
      choose_OCODE0 @branch
      each_OCODE1 do |ocode1|
        puts "OCODE1: #{ocode1}"
        each_S2 do |s2|
          print "S2: #{s2} "
          rows = Cache.try_json "yonsei-#{@branch}-#{ocode1}-#{s2}" do
            do_search
            rows = []
            1.upto Float::INFINITY do |page|
              print "##{page} "
              rows.concat fetch_rows
              break unless next_page?
              move_to_next_page
            end
            rows
          end
          rows.each do |e|
            yield build_lecture s2, e
          end
          puts rows.size
        end
      end
    rescue Interrupt
      @web_driver.quit if @web_driver
    else
      @web_driver.quit if @web_driver
    end

    def each(&block)
      lecture_map = {}
      each_row do |lecture|
        if l = lecture_map[lecture.litid]
          domains = l.domain.split(',') + lecture.domain.split(',')
          l.domain = domains.sort.uniq.join(',')
        else
          lecture_map[lecture.litid] = lecture
        end
      end
      lecture_map.each_value(&block)
    end

    include Enumerable
  end
end
