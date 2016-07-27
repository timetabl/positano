require 'set'
require 'selenium-webdriver'
require 'nokogiri'
require_relative 'cache'

module Sogang
  class Web
    KEYS = Selenium::WebDriver::Keys
    UNIV_NAME = 'sogang'

    def initialize(semester)
      @id = 1
      @semester = semester
    end

    attr_reader :id, :semester

    def choose_year(web_driver, year)
      elem = web_driver.find_element id: 'WD18'
      visited = Set.new
      loop do
        value = elem['value'][0..3].to_i
        raise "cannot find year <#{year}>" if visited.include? value
        visited.add value
        break if value == year
        elem.send_keys KEYS[value > year ? :down : :up]
      end
      unless visited.empty?
        elem.send_keys KEYS[:enter]
        sleep 2
      end
    end

    def choose_semester(web_driver, term)
      elem = web_driver.find_element id: 'WD33'
      case term
      when 1
        elem.send_keys KEYS[:home]
      when 2
        elem.send_keys KEYS[:home], KEYS[:down], KEYS[:down]
      else
        raise RangeError, "invalid term <#{term}>", caller
      end
      elem.send_keys KEYS[:enter]
      sleep 2
    end

    def wait_result(web_driver)
      elem = web_driver.find_element id: 'WD_DoubleSubmitProtect'
      Selenium::WebDriver::Wait.new(timeout: 10).until { !elem.displayed? }
    end

    def fetch_content(web_driver)
      web_driver.find_element(partial_link_text: '검색').send_keys KEYS[:space]
      sleep 3
      wait_result web_driver
      web_driver.execute_script 'return document.getElementById("WD91-content").innerHTML'
    end

    LESSON_RE = %r<
      ((?:월|화|수|목|금|토|일)(?:,(?:월|화|수|목|금|토|일))*)\s*
      (\d\d):(\d\d)~(\d\d):(\d\d)(?:\s+(\w+))?
    >mx

    class Lesson < ::Lesson
      def t2p time
        p = (time.to_i - 450) / 90
        raise RangeError, "out of range: #{p}", caller unless (0..10).include? p
        p
      end
    end

    DAY2N = Hash['월화수목금토일'.chars.zip(1..7)]

    def parse_lessons(text)
      lessons = []
      text.scan(LESSON_RE) do |m|
        days = m[0] || ''
        time = m[1].to_i * 60 + m[2].to_i
        period = m[3].to_i * 60 + m[4].to_i - time
        location = m[5] || ''
        days.scan(/월|화|수|목|금|토|일/) do |d|
          lesson = Lesson.new
          lesson.day = DAY2N[d]
          lesson.time = time
          lesson.period = period
          lesson.location = location
          lessons.push lesson
        end
      end
      lessons
    end

    def parse_row(domain_name, fields)
      _, _, division, major, code, klass, title, _, credits, time_and_location,
      _, lecturer, _, english, abeek, _, _, exam_date, _, years, note3,
      note2, note = fields

      return if division != '학부'
      return if title == '수강신청 테스트과목'

      raise "invalid code <#{code}>" if code !~ /\A[A-Z]{3}[A-Z\d]\d{3}\z/
      raise "invalid class <#{klass}>" if klass !~ /\A\d\d\z/
      raise "invalid credits <#{credits}>" if credits !~ /\A\d\.0\z/

      lecturer = '' if lecturer == '교수진'

      year =  if years == '전학년'
                (1 << 6) - 1
              else
                years.scan(/\d+/).map { |e| 1 << e.to_i >> 1 }.reduce(0, &:|)
              end

      remarks = []
      # remarks.push '%s명' % (capacity) unless capacity.empty?
      remarks.push '영어강의' unless english.empty?
      # remarks.push '시험:' + (exam_date) unless exam_date.empty?
      # remarks.push '권장:' + target unless target.empty?
      remarks.push note unless note.empty?
      remarks.push note2 unless note2.empty?
      remarks.push note3 unless note3.empty?
      remarks.push 'ABEEK' unless abeek.empty?
      remark = remarks.join(' ')

      closed = remark.include? '폐강'

      lecture = Lecture.new UNIV_NAME, @semester.to_i, "#{code}-#{klass}"
      lecture.domain = domain_name
      lecture.year = year
      lecture.title = title
      lecture.credits = closed ? 0 : credits.to_i
      lecture.lecturer = lecturer
      lecture.remark = remark
      lecture.lessons.replace parse_lessons(time_and_location) unless closed
      lecture
    rescue
      raise $!.class, "#{$!} on #{fields.inspect}", $@
    end

    def each_row
      web_driver = Selenium::WebDriver.for :firefox
      web_driver.get 'http://sis109.sogang.ac.kr/sap/bc/webdynpro/sap/zcmw9016' \
                     '?sap-language=KO#...'
      web_driver.switch_to.frame web_driver.find_elements(tag_name: 'frame').first
      sleep 1
      choose_year web_driver, @semester.year
      choose_semester web_driver, @semester.term
      web_driver.find_element(id: 'WD63').send_keys(KEYS[:down], KEYS[:enter])
      sleep 2

      prev_domain_name = ''
      loop do
        elem = web_driver.find_element id: 'WD75'
        elem.send_keys KEYS[:down]
        domain_name = elem['value'].strip
        break if domain_name == prev_domain_name
        next if domain_name == '전인교육원(전체)'
        prev_domain_name = domain_name

        print "#{domain_name}..."

        html = Cache.try "sogang-#{domain_name}" do
          elem.send_keys KEYS[:enter]
          sleep 3
          fetch_content web_driver
        end
        rows = Nokogiri::HTML(html).css('tr').map do |tr|
          tr.css('td').map(&:text).map! { |e| e.gsub("\u00a0", ' ').strip }
        end
        count = 0
        rows.each do |fields|
          lecture = parse_row domain_name, fields
          if lecture
            count += 1
            yield lecture
          end
        end
        puts count
        sleep 1
      end
    rescue Interrupt
      web_driver.quit if web_driver
    else
      web_driver.quit if web_driver
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
