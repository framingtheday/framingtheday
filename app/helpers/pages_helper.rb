module PagesHelper
 def colors(percent)
    if percent >=80.0
      "id=eighty"
    elsif percent >=70.0
      "id=seventy"
    end
  end

end
