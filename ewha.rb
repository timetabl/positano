require 'faraday'
require 'nokogiri'
require_relative 'structs'
require_relative 'cache'

module Ewha
  class Lesson < ::Lesson
    def t2p time
      p = (time.to_i - 390) / 90
      raise RangeError, "out of range: #{p}", caller unless (0..16).include? p
      p
    end
  end

  class Web
    def initialize(semester)
      @id = 4
      @univ_name = 'ewha'
      @semester = semester
      @semester_name = "#{semester.year}#{semester.term}"
      @conn = Faraday.new url: 'http://eureka.ewha.ac.kr' do |faraday|
        faraday.request :url_encoded
        faraday.adapter Faraday.default_adapter
      end
    end

    attr_reader :id, :semester

    def fetch_html page
      sleep 10 # cool down

      body = {
        # searchText: '%EB%85%84%EB%8F%84%2F%ED%95%99%EA%B8%B0+%3A+2015+-+1%ED%95%99%EA%B8%B0++%2C%EA%B5%90%EA%B3%BC%EB%AA%A9%EA%B5%AC%EB%B6%84+%3A+%EC%A0%84%EC%B2%B4++%2C%EA%B5%90%EC%96%91%EC%98%81%EC%97%AD+%3A+%EC%A0%84%EC%B2%B4++%2C%EB%8C%80%ED%95%99+%3A+%EC%A0%84%EC%B2%B4++%2C%ED%95%99%EA%B3%BC%2F%EC%A0%84%EA%B3%B5+%3A+%EC%A0%84%EC%B2%B4++%2C%ED%95%99%EB%85%84+%3A+%EC%A0%84%EC%B2%B4++%2C%EA%B5%90%EA%B3%BC%EB%AA%A9%EB%AA%85+%3A+%25++%2C%EC%9B%90%EC%96%B4%EA%B0%95%EC%9D%98+%3A+%ED%95%B4%EB%8B%B9%EC%97%86%EC%9D%8C++%2C%EC%88%98%EC%97%85%EC%9A%94%EC%9D%BC+%3A+%EC%A0%84%EC%B2%B4++%2C%EC%88%98%EC%97%85%EA%B5%90%EC%8B%9C+%3A+%EC%A0%84%EC%B2%B4',
        searchYn: 'Y',
        excelYn: '',
        pageNum: page.to_s,
        groupCd: '20',
        yearTermCd: "#{@semester_name}0",
        viewKindCd: '',
        areaCd: '',
        univCd: '',
        clsMajCd: '',
        gradeYear: '',
        queryCond: '',
        queryCont: '',
        subjectCd: '',
        subjectNm: '%',
        profName: '',
        orgLangCd: '',
        lectureDay: '',
        lectureHour: '',
      }

      res = @conn.post '/eureka/hs/sg/openHssg504021q.do?popupYn=Y', body,
        origin: 'http://eureka.ewha.ac.kr',
        user_agent: 'Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.3; WOW64; Trident/7.0)',
        referer: 'http://eureka.ewha.ac.kr/eureka/hs/sg/openHssg504021q.do?popupYn=Y'

      raise "status code is #{res.status}" if res.status != 200

      res.body.force_encoding Encoding::UTF_8
    end

    def fetch_and_cache_html page
      Cache.try "ewha-#{page}" do
        fetch_html page
      end
    end

    def build_remark column
      a = []
      a.push "영어강의" unless column[18].empty?
      a.push "원어강의:#{column[19]}" unless column[19].empty?
      a.push "온라인강의" unless column[20].empty?
      a.push "인원제한:#{column[21]}" unless column[21].empty?
      a.push column[22] unless column[22].empty?
      a.join ' '
    end

    def compact_spaces text
      text.strip.gsub(/\s{2,}/, ' ')
    end

    def figure_domain type, section, domain
      case type
      when '교양'.freeze
        section
      when '교선'.freeze
        '교양선택'.freeze
      when '비교'.freeze
        '비사대교직'.freeze
      when '전선교'.freeze
        '전공선택(교직)'.freeze
      when '대기'.freeze
        '대학기초'.freeze
      when '전기'.freeze
        '전공기초'.freeze
      when '전선'.freeze, '전필'.freeze
        domain
      else
        raise RangeError, "unknown type: #{type};#{section};#{domain}", caller
      end
    end

    def parse_html html
      Nokogiri::HTML(html).css('#wrap table.tbl_type2 tr').map { |tr|
        tr.css('br').each do |br|
          br.add_next_sibling "\n"
          br.unlink
        end
        tr.element_children.map { |e| e.text.gsub(/\u00a0|\t/, ' ').strip }
      }.select { |e| e.size == 23 && e.first =~ /\A\d+\z/ }.select { |e|
        if e[1] =~ /\A\d{5}\z/
          true
        else
          warn "skip code: #{e[1]}"
          false
        end
      }.map { |e|
        begin
          raise "invalid code <#{e[1]}>" if e[1] !~ /\A\d{5}\z/
          raise "invalid class <#{e[2]}>" if e[2] !~ /\A\d\d\z/
          lecture = Lecture.new @univ_name, @semester_name, "#{e[1]}-#{e[2]}"
          lecture.title = compact_spaces e[3]
          lecture.domain = compact_spaces figure_domain e[4], e[5], e[6]
          lecture.year = e[7]
          lecture.lecturer = compact_spaces(e[8].gsub(',', ' ')).split(/\s*\/\s*/).sort.join(',')
          lecture.credits = e[9].to_f
          lecture.remark = build_remark e
          lecture.lessons.replace parse_lessons e[11], e[12], e[13]
          lecture
        rescue
          raise $!.class, "#{$!} on #{e.inspect}", $@
        end
      }
    end

    DAY_NAME_TO_ID = {
      '월' => 1,
      '화' => 2,
      '수' => 3,
      '목' => 4,
      '금' => 5,
      '토' => 6,
      '일' => 7,
    }

    def parse_lessons daystr, timestr, locationstr
      day_texts = daystr.split "\n"
      time_texts = timestr.split "\n"
      loc_texts = locationstr.split "\n"
      if day_texts.size != time_texts.size || loc_texts.size > time_texts.size
        if time_texts.any? { |e| e != time_texts.first }
          raise "count mismatch: #{day_texts.size} == #{time_texts.size} <= #{loc_texts.size}"
        end
        time_texts = [ time_texts.first ] * loc_texts.size
      end
      day_texts.zip(time_texts, loc_texts).map do |d, t, l|
        m = t.match(/\A(\d+)~(\d+)\z/)
        raise "cannot parse lesson: #{d};#{t};#{l}" unless m
        start = m[1].to_i
        lesson = Lesson.new DAY_NAME_TO_ID[d], start * 90 + 390
        lesson.period = (m[2].to_i - start + 1) * 90 - 15
        lesson.location = (l || '').strip
        lesson
      end
    end

    def create_chapel subid, options = {}
      lecture = Lecture.new @univ_name, @semester_name, "00000-0#{subid}"
      lecture.domain = '채플'
      lecture.year = 0
      lecture.credits = 0
      lecture.title = '채플'
      lecture.remark = options[:remark]
      lecture.lecturer = ''
      lesson = Lesson.new options[:day], options[:time] * 90 + 390
      lesson.period = 30
      lesson.location = '대강당'
      lecture.lessons.replace [ lesson ]
      lecture
    end

    def each &block
      Enumerator.new { |y|
        y.yield create_chapel 1, day: 1, time: 2, remark: '10:00-10:30 인문과학대학 1학년, 예술대학 1학년, 사범대학 1학년, 법과대학 1학년, 경영대학 1학년, 스크랜튼대학 2학년'
        y.yield create_chapel 2, day: 2, time: 2, remark: '10:00-10:30 자연과학대학 4학년, 공과대학 4학년, 예술대학 2,4학년, 건강과학대학 1학년, 스크랜튼대학 1학년, 음악대학 4학년, 조형예술대학 4학년, 생활환경대학 4학년'
        y.yield create_chapel 3, day: 3, time: 2, remark: '10:00-10:30 예술대학 3학년, 사범대학 4학년, 법과대학 4학년, 경영대학 4학년, 음악대학 3학년 조형예술대학 3학년, 생활환경대학 3학년, 국제학부 3,4학년'
        y.yield create_chapel 4, day: 4, time: 2, remark: '10:00-10:30 자연과학대학 1,2학년, 사범대학 2학년, 경영대학 2학년, 간호과학대학 2학년, 약학대학 1,2학년, 체육과학대학 4학년'
        y.yield create_chapel 5, day: 5, time: 2, remark: '10:00-10:30 인문과학대학 3학년, 사회과학대학 3학년, 사범대학 3학년, 경영대학 3학년, 약학대학 3학년'
        y.yield create_chapel 6, day: 3, time: 3, remark: '11:30-12:00 인문과학대학 4학년, 사회과학대학 4학년, 공과대학 1,2학년, 체육과학대학 3학년, 법과대학 2학년, 간호과학대학 4학년, 건강과학대학 4학년'
        y.yield create_chapel 7, day: 4, time: 3, remark: '11:30-12:00 인문과학대학 2학년, 사회과학대학 1,2학년, 자연과학대학 3학년, 공과대학 3학년, 건강과학대학 3학년, 간호과학대학 3학년'

        1.upto Float::INFINITY do |e|
          slice = parse_html fetch_and_cache_html e
          break if slice.empty?
          slice.each do |a|
            y.yield a
          end
        end
      }.each &block
    end

    include Enumerable
  end
end
