class Lecture < Struct.new(:univ, :semester, :litid)
  DAY_NAME = %w[ ? 월 화 수 목 금 토 일 ]

  attr_accessor :title, :year, :domain, :credits, :lecturer, :remark
  attr_reader :lessons

  def initialize univ, semester, litid
    super()
    self.univ = univ
    self.semester = semester
    self.litid = litid
    @title = ''
    @year = 0
    @domain = ''
    @credits = 0
    @lecturer = ''
    @remark = ''
    @lessons = []
  end

  UNIV_NAME_TO_ID = {
    'sogang' => 1,
    'yonsei' => 2,
    'wonju' => 3,
    'ewha' => 4,
    'hongik' => 5
  }

  def univ= v
    t = v.is_a?(String) ? UNIV_NAME_TO_ID[v] : v
    raise RangeError, "invalid univ: #{v}", caller unless (1..4).include? t
    super t
  end

  def semester= v
    t = v.is_a?(String) ? v[0..3].to_i - 2007 << 1 | v[4].to_i - 1 : v
    raise RangeError, "invalid semester: #{v}", caller unless (1..19).include? t
    super t
  end

  def title= v
    raise ArgumentError, "empty title", caller if v.empty?
    @title = v
  end

  def year= v
    t = v.is_a?(String) ?
      v.split(',').map { |e| 1 << e.to_i >> 1 }.reduce(0, &:|) :
      v
    raise RangeError, "invalid year: #{v}", caller unless (0..0x3f).include? t
    @year = t
  end

  def domain= v
    # if v !~ %r/\A\S+\z/
    if v.empty?
      raise ArgumentError, "invalid domain: #{v}", caller
    end
    @domain = v
  end

  def credits= v
    unless [ 0, 0.5, 1.0, 1.5, 2.5, 2.0, 3.0, 3.5, 4.5, 4.0, 5.0, 5.5, 9.0, 6.0, 12.0, 15.0 ].include? v
      raise RangeError, "invalid credits: #{v}", caller
    end
    @credits = v
  end

  def course_id= v
    raise TypeError, "course_id cannot be nil", caller unless v
    @course_id = v
  end

  def timetext
    top = nil
    stack = []
    @lessons.sort_by { |e| [ e.day, e.time ] }.each do |e|
      if top && top[0] == e.day && top[2] + 1 >= e.start_period
        top = [ top[0], top[1], [ top[2], e.end_period ].max ]
      else
        stack.push top if top
        top = [ e.day, e.start_period, e.end_period ]
      end
    end
    stack.push top if top

    lastday = 0
    text = ''
    stack.each do |e|
      text.concat lastday == e[0] ? ',' : DAY_NAME[e[0]]
      text.concat e[1].to_s
      text.concat '-' + e[2].to_s if e[1] != e[2]
      lastday = e[0]
    end

    text.sub! /([월화수목금토일])(\d+(?:-\d+)?)(?=[월화수목금토일]\2(?!-|\d))/, '\1'
    text.sub! '월화수목금', '월-금'
    text
  end

  def locationtext
    @lessons.map(&:location).compact.sort.uniq.join(',')
  end
end

class Lesson < Struct.new(:day, :time)
  attr_accessor :period, :location

  def initialize(*)
    super
    @period = 0
    @location = ''
  end

  def day= day
    raise RangeError, "invalid day: #{day}", caller unless (1..7).include? day
    super
  end

  def time= time
    raise RangeError, "invalid time: #{time}", caller unless (0..9999).include? time
    super
  end

  def period= period
    raise RangeError, "invalid period: #{period}", caller unless (1..480).include? period
    @period = period
  end

  def location= location
    if !location.nil? && !location.is_a?(String)
      raise TypeError, "invalid location: #{location}", caller
    end
    @location = location
  end

  def t2p time
    raise NotImplementedError
  end

  def start_period
    t2p time
  end

  def end_period
    t2p time + @period - 1
  end

  def mask_of_day d
    if d == day
      (1 << end_period + 1) - (1 << start_period)
    else
      0
    end
  end
end

class Semester
  def initialize(year, term)
    @year = year
    @term = term
    @to_i = (year - 2007) << 1 | (term - 1)
    unless (1..19).include? @to_i
      raise RangeError, "year #{year} and term #{term} is out of range", caller
    end
  end

  attr_reader :year, :term, :to_i
end
