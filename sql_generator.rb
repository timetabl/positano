module SQLGenerator
  module_function

  def sqlize(query, *params)
    query.gsub /\?/ do
      param = params.shift
      case param
      when nil
        'NULL'
      when Numeric
        param.to_s
      else
        "'" << param.to_s.gsub(/'/, "''") << "'"
      end
    end
  end

  def generate(univ_module, output)
    lectures = univ_module.to_a
    lectures.uniq!
    lectures.sort_by! &:litid

    output.puts 'BEGIN;'
    output.puts 'SET NAMES utf8mb4;'
    lectures.each do |lecture|
      output.puts sqlize 'INSERT IGNORE INTO course (univ, title, lecturer) VALUES (?, ?, ?);',
        lecture.univ, lecture.title, lecture.lecturer
      output.puts sqlize 'SET @course_id = (SELECT id FROM course WHERE univ = ? AND title = ? AND lecturer = ?);',
        lecture.univ, lecture.title, lecture.lecturer
      output.puts sqlize 'INSERT IGNORE INTO lectures (univ, semester, litid, domain, year, title, credits, lecturer, remark, time_txt, location_txt, course_id, competitors) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, @course_id, 0);',
        lecture.univ, lecture.semester, lecture.litid, lecture.domain, lecture.year, lecture.title, lecture.credits, lecture.lecturer, lecture.remark, lecture.timetext, lecture.locationtext
      output.puts sqlize 'UPDATE lectures SET domain = ?, year = ?, title = ?, credits = ?, lecturer = ?, remark = ?, time_txt = ?, location_txt = ?, course_id = @course_id WHERE univ = ? AND semester = ? AND litid = ?;',
        lecture.domain, lecture.year, lecture.title, lecture.credits, lecture.lecturer, lecture.remark, lecture.timetext, lecture.locationtext, lecture.univ, lecture.semester, lecture.litid
      output.puts sqlize 'SET @lecture_id = (SELECT id FROM lectures WHERE univ = ? AND semester = ? AND litid = ?);',
        lecture.univ, lecture.semester, lecture.litid
      output.puts 'DELETE FROM lessons WHERE id = @lecture_id;'
      lecture.lessons.each do |lesson|
        output.puts sqlize 'INSERT INTO lessons (id, day, time, period, location, day1, day2, day3, day4, day5, day6, day7) VALUES (@lecture_id, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
          lesson.day, lesson.time, lesson.period, lesson.location, lesson.mask_of_day(1), lesson.mask_of_day(2), lesson.mask_of_day(3), lesson.mask_of_day(4), lesson.mask_of_day(5), lesson.mask_of_day(6), lesson.mask_of_day(7)
      end
    end
    output.puts 'COMMIT;'
  end
end
