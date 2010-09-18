class PagesController < ApplicationController

require 'open-uri'
require 'csv'


  def display
    @user_input = { :stocksymbol => params[:stocksymbol].to_s.upcase, :startdate => DateTime.now, :period => params[:period], :lookback => params[:lookback], :lookforward => params[:lookforward] , :openprice => params[:openprice]}
    
    begin
     period = @user_input[:period].to_i
     period = 100 if period < 100
    rescue
     period = 1000
    end
    @user_input[:period] =  period.to_s
    
    begin
      lookback = @user_input[:lookback].to_i
      lookback = 2 if lookback > 300 or lookback < 1
    rescue
      lookback = 2
    end
    @user_input[:lookback] = lookback.to_s
    
    begin
      lookforward = @user_input[:lookforward].to_i
      lookforward = 2 if lookforward < 1
     rescue
      lookforward = 2
    end
    @user_input[:lookforward] = lookforward.to_s
    
    # should test to make sure lookback, lookforward are reasonable with respect to period.  if period is too short
    # then not statistically valid.
    yahoo_csv =  get_adjusted_close( @user_input[:stocksymbol], @user_input[:startdate], period )
    csv = csv_to_number(yahoo_csv)
    # adjust open price if entered....
    if params[:openprice].length > 0
      begin
        csv[0][:stockopen] = params[:openprice].to_f 
      rescue
      end
    end
    csv_crosses = look_back(csv, lookback, lookforward)
    @cross_percent = crosses(csv_crosses, lookback, lookforward)
    csv_crosses
  end
  def home
    @user_input = { :stocksymbol => 'IWM', :period => 1000, :lookback => 2, :lookforward => 2}
  end
 
private
def get_adjusted_close( stock_symbol, today, days )
  stock_symbol.strip!
  today = DateTime.now
  start = today - ( days * 3 / 2 )
  # yahoo csv file is
  # date (MM/DD/YYYY), open, high, low, close, volume, adjusted close
  # sorted by most recent date first
  url="http://download.finance.yahoo.com/d/quotes.csv?s=#{stock_symbol}&f=sl1d1t1c1ohgv&e=.csv"
  csv_today = CSV.parse(open(url).read)

  url = "http://ichart.finance.yahoo.com/table.csv?s=#{stock_symbol}&d=#{today.month}&e=#{today.day}&f=#{today.year}&g=d&a=#{start.month-1}&b=#{start.day}&c=#{start.year}&ignore=.csv"
  csv = CSV.parse(open(url).read)
  # create row for today.  if no data, create dummy row anyway so that pivots and lookback can be calculated
  # if Date.parse(csv[1][0]) != Date.parse(csv_today[0][2])
  d = DateTime.now
  d = Date::civil($3.to_i, $1.to_i, $2.to_i) if csv_today[0][2] =~ %r{(\d+)/(\d+)/(\d+)}
   
    csv.insert(1, [d.to_s, csv_today[0][5], csv_today[0][6], csv_today[0][7], csv_today[0][1], csv_today[0][8], csv_today[0][1] ] )
end

def csv_to_number(csv)
  csv_converted = []
  # first convert to numbers (and date)
  csv.each do | ln |
    csv_converted << { :stockdate => Date.parse(ln[0]), :stockopen => ln[1].to_f, :stockhigh => ln[2].to_f,
      :stocklow => ln[3].to_f, :stockclose => ln[4].to_f, :stockvolume => ln[5].to_f, 
      :adj_close => ln[6].to_f, :range => (ln[2].to_f - ln[3].to_f) } if ln[0] =~ /\d\d\d\d-\d\d-\d\d/
   end
   csv_converted
end


def look_back(csv, days_back, days_forward)
    (csv.length-days_back).times do | i |
      # calculate pivots 
      csv[i].merge!(pivot_values(csv[i+1]))
      csv[i].merge!(median_range(csv, i))
      stockhigh = csv[i][:stockhigh]
      stocklow = csv[i][:stocklow]
      # calculate pivot crosses
      csv[i][:open_pivot_position] = open_pivot_position(csv[i])
      csv[i][:pivot_cross] = ( csv[i][:pivot] < stockhigh and csv[i][:pivot] > stocklow ) ? 1 : 0
      csv[i][:r1_cross] = ( csv[i][:r1] < stockhigh and csv[i][:r1] > stocklow ) ? 1 : 0
      csv[i][:r2_cross] = ( csv[i][:r2] < stockhigh and csv[i][:r2] > stocklow ) ? 1 : 0
      csv[i][:r3_cross] = ( csv[i][:r3] < stockhigh and csv[i][:r3] > stocklow ) ? 1 : 0
      csv[i][:s1_cross] = ( csv[i][:s1] < stockhigh and csv[i][:s1] > stocklow ) ? 1 : 0
      csv[i][:s2_cross] = ( csv[i][:s2] < stockhigh and csv[i][:s2] > stocklow ) ? 1 : 0
      csv[i][:s3_cross] = ( csv[i][:s3] < stockhigh and csv[i][:s3] > stocklow ) ? 1 : 0
      # calculate yesterday high/low crosses
      csv[i][:yesterday_high_cross] = (csv[i+1][:stockhigh] < stockhigh and csv[i+1][:stockhigh] > stocklow ) ? 1 : 0
      csv[i][:yesterday_low_cross] = (csv[i+1][:stocklow] < stockhigh and csv[i+1][:stocklow] > stocklow ) ? 1 : 0
      # calculate look back
      csv[i].merge!(days_back_values(csv, i+1, days_back))
      csv[i][:open_range] =  (csv[i][:stockopen]-csv[i][:lookback_low])/(csv[i][:lookback_high]-csv[i][:lookback_low])
      
      # now calculate look forward
      forward_low = csv[i][:stocklow]
      forward_high = csv[i][:stockhigh]
      if days_forward > 1 and i > days_forward 
       (1..(days_forward-1)).each do | j |
        forward_low = csv[i-j][:stocklow] if forward_low > csv[i-j][:stocklow]
        forward_high = csv[i-j][:stockhigh] if forward_high < csv[i-j][:stockhigh]
       end
      end
      csv[i][:lookfoward_high] = forward_high
      csv[i][:lookfoward_low] = forward_low
      # calculate lookfoward crosses
      # puts   i," ", csv[i][:stockdate], " ", csv[i][:lookback_high] ,  " ",csv[i][:lookback_low]
      pts = []
      12.times do | j |
        pt =   ( j - 3.0 ) / 5.0 * ( csv[i][:lookback_high] - csv[i][:lookback_low] ) + csv[i][:lookback_low] 
        pts[j] = ( forward_high > pt and forward_low < pt ) ? 1 : 0
      end
      csv[i][:cross_pts] = pts  
    end
    csv
end

def crosses(csv_crosses, days_back, days_forward)
  # first row is today.
  today_pivot_position = csv_crosses[0][:open_pivot_position]
  today_open_range = (csv_crosses[0][:open_range] * 10.0).floor
  total_rows = 0
  total_pivot_rows =0
  total_r3_cross = 0
  total_r2_cross = 0
  total_r1_cross = 0
  total_pivot_cross = 0
  total_s1_cross = 0
  total_s2_cross = 0
  total_s3_cross = 0
  
  prior_high_count = 0
  prior_high_cross = 0
  prior_low_count = 0
  prior_low_cross = 0
  
  open_prior_high = ( csv_crosses[0][:stockopen] - csv_crosses[1][:stockhigh]) / csv_crosses[0][:median_range]
  open_prior_low = ( csv_crosses[0][:stockopen] - csv_crosses[1][:stocklow]) / csv_crosses[0][:median_range]
  range_crosses = [0, 0,0,0,0,0,0,0,0,0,0,0]
  # skip most recent - should be at least look forward days.
  (days_forward..(csv_crosses.length-days_back-1)).each do |i|
  
    if today_pivot_position == csv_crosses[i][:open_pivot_position]
      total_pivot_rows += 1
      total_r3_cross += csv_crosses[i][:r3_cross]
      total_r2_cross += csv_crosses[i][:r2_cross]
      total_r1_cross += csv_crosses[i][:r1_cross]
      total_pivot_cross += csv_crosses[i][:pivot_cross]
      total_s1_cross += csv_crosses[i][:s1_cross]
      total_s2_cross += csv_crosses[i][:s2_cross]
      total_s3_cross += csv_crosses[i][:s3_cross]
    end

    if today_open_range == (csv_crosses[i][:open_range] * 10.0).floor
      range_crosses.length.times { | j | range_crosses[j] += csv_crosses[i][:cross_pts][j] }
      total_rows += 1
    end
    
    row_prior_high = ( csv_crosses[i][:stockopen] - csv_crosses[i+1][:stockhigh]).to_f / csv_crosses[i][:median_range]
  #  puts   "prior high = #{row_prior_high}  #{csv_crosses[i][:stockopen]} #{csv_crosses[i+1][:stockhigh]} #{csv_crosses[i][:median_range]} #{open_prior_high}"
   
    if open_prior_high - 0.03 < row_prior_high and open_prior_high + 0.03 > row_prior_high
      prior_high_count += 1
      prior_high_cross += csv_crosses[i][:yesterday_high_cross]
    end
    row_prior_low = ( csv_crosses[i][:stockopen] - csv_crosses[i+1][:stocklow]).to_f / csv_crosses[i][:median_range]
    if open_prior_low - 0.03 < row_prior_low and open_prior_low + 0.03 > row_prior_low
      prior_low_count += 1
      prior_low_cross += csv_crosses[i][:yesterday_low_cross]
    end
 #    puts   "prior low = #{row_prior_low}  #{csv_crosses[i][:stockopen]} #{csv_crosses[i][:stockhigh]}  #{csv_crosses[i][:stocklow]} #{ csv_crosses[i+1][:stocklow]} yesterday cross #{csv_crosses[i][:yesterday_low_cross]} #{csv_crosses[i][:median_range]} #{open_prior_low} "
  end
 # puts "position #{today_pivot_position} total pivot #{total_pivot_rows} #{total_r2_cross} #{total_r1_cross} #{total_pivot_cross} ##{total_s1_cross} #{total_s2_cross}"
 #  print "range #{today_open_range} total #{total_rows} "
 # range_crosses.length.times { | i | print "#{range_crosses[i]} " }
 # puts
 
      pts = []
      12.times do | j |
        pts[j] =   ( j - 3.0 ) / 5.0 * ( csv_crosses[0][:lookback_high] - csv_crosses[0][:lookback_low] ) + csv_crosses[0][:lookback_low] 
      end
   
  
  { :today_pivot_position=> today_pivot_position,
  :pivot => csv_crosses[0][:pivot],
  :r3 => csv_crosses[0][:r3],
  :r2 => csv_crosses[0][:r2],
  :r1 => csv_crosses[0][:r1],
  :s1 => csv_crosses[0][:s1],
  :s2 => csv_crosses[0][:s2],
    :s3 => csv_crosses[0][:s3],
  :total_rows=>		total_rows,
:total_pivot_rows=>		total_pivot_rows,
:total_r3_cross=>		total_r3_cross,
:total_r2_cross=>		total_r2_cross,
:total_r1_cross=>		total_r1_cross,
:total_pivot_cross=>		total_pivot_cross,
:total_s1_cross=>		total_s1_cross,
:total_s2_cross=>		total_s2_cross,
:total_s3_cross=>		total_s3_cross,
:range_crosses=>		range_crosses,
:cross_pts => pts ,
:lookback_high => csv_crosses[0][:lookback_high],
:lookback_low => csv_crosses[0][:lookback_low],
:today_open =>csv_crosses[0][:stockopen],
:today_high => csv_crosses[0][:stockhigh],
:today_low => csv_crosses[0][:stocklow],
:today_last => csv_crosses[0][:stockclose],
:yesterday_open =>csv_crosses[1][:stockopen],
:yesterday_high => csv_crosses[1][:stockhigh],
:yesterday_low => csv_crosses[1][:stocklow],
:yesterday_last => csv_crosses[1][:stockclose],
:median_range => csv_crosses[0][:median_range],
:prior_high_count => prior_high_count ,
:prior_high_cross => prior_high_cross,
:prior_low_count => prior_low_count ,
:prior_low_cross => prior_low_cross

}
end

def pivot_values(csv)
      pivot_value = (csv[:stockhigh] + csv[:stocklow] + csv[:stockclose]) / 3 
      high_low = csv[:stockhigh] - csv[:stocklow]
      { :pivot => pivot_value,
       :r1 => pivot_value * 2 - csv[:stocklow] ,
       :r2 => pivot_value + high_low ,
       :r3 => pivot_value + 2 * high_low,
       :s1 => pivot_value * 2 - csv[:stockhigh] ,
       :s2 => pivot_value - high_low,
       :s3 => pivot_value - 2 * high_low }
end

def days_back_values(csv, start, days)
  back_low = csv[start][:stocklow]
  back_high = csv[start][:stockhigh]
  if days>1 
    ((1)..(days-1)).each do | d |
      back_low = csv[start+d][:stocklow] if back_low > csv[start+d][:stocklow]
      back_high = csv[start+d][:stockhigh] if back_high < csv[start+d][:stockhigh]
    end
  end
  { :lookback_high => back_high, :lookback_low => back_low }

end

def open_pivot_position(csv )
 if csv[:stockopen] < csv[:s2 ]  
    open_pivot = 1
  elsif csv[:stockopen] < csv[:s1 ] 
    open_pivot = 2
  elsif csv[:stockopen] < csv[:s1] + (csv[:pivot ] - csv[:s1] ) * 0.25  
    open_pivot = 3
  elsif csv[:stockopen] < csv[:s1] + (csv[:pivot ] - csv[:s1] ) * 0.50  
    open_pivot = 4
  elsif csv[:stockopen] < csv[:s1] + (csv[:pivot ] - csv[:s1] ) * 0.75  
    open_pivot = 5    
  elsif csv[:stockopen] < csv[:pivot ] 
    open_pivot = 6
  elsif csv[:stockopen] < csv[:pivot] + (csv[:r1 ] - csv[:pivot] ) * 0.25  
    open_pivot = 7
  elsif csv[:stockopen] < csv[:pivot] + (csv[:r1 ] - csv[:pivot] ) * 0.50  
    open_pivot = 8
  elsif csv[:stockopen] < csv[:pivot] + (csv[:r1 ] - csv[:pivot] ) * 0.75  
    open_pivot = 9
  elsif csv[:stockopen] < csv[:r1] 
    open_pivot = 10
  elsif csv[:stockopen] < csv[:r2] 
    open_pivot = 11
  else
    open_pivot = 12
  end
  open_pivot
end

def median_range(csv, i)
  a = []
  10.times { | whch | a << csv[i+whch+1][:range] if csv[i+whch+1] }
  a.sort!
  a_length = a.length
  { :median_range => (a[a_length/2]+a[a_length/2-1])/2.0 }
end

end
