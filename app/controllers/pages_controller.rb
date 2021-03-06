class PagesController < ApplicationController

require 'open-uri'
require 'csv'


  def display
    @user_input = { :stocksymbol => params[:stocksymbol].to_s.upcase, :startdate => DateTime.now, :period => params[:period], :lookback => params[:lookback], :lookforward => params[:lookforward] , :openprice => params[:openprice]}
    # validate user input
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
    #
    # get data from yahoo!
    #
    yahoo_csv =  get_adjusted_close( @user_input[:stocksymbol], @user_input[:startdate], period )
    #
    # convert to numeric, data values
    #
    csv = csv_to_number(yahoo_csv)
    # adjust open price if entered....
    if params[:openprice].length > 0
      begin
        csv[0][:stockopen] = params[:openprice].to_f 
        csv[0][:stockdate] = DateTime.now.to_date
      rescue
      end
    end
    #
    # calculate historical values - if high, low, etc were crossed on a particular day
    #
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
# convert each line to a hash
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
#
# calculate crosses
#
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
      csv[i][:yesterday_close_cross] = (csv[i+1][:stockclose] < stockhigh and csv[i+1][:stockclose] > stocklow ) ? 1 : 0
      # adjust for size of range (trying to remove some of the volatility from the calculations)
      csv[i][:yesterday_high_distance] = ( csv[i][:stockopen] - csv[i+1][:stockhigh] ) / csv[i][:median_long_range] 
      csv[i][:yesterday_low_distance] = ( csv[i][:stockopen] - csv[i+1][:stocklow] ) / csv[i][:median_long_range] 
      csv[i][:yesterday_close_distance] = ( csv[i][:stockopen] - csv[i+1][:stockclose] ) / csv[i][:median_long_range] 
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
# at this point, the csv_crosses is an array with the original high/low info, plus additional info
#   on if various points (prior day's high/low/close), pivot points, were crossed.
#  now go through that data, and based on today's opening price, look at each row in csv_crosses.
#   if csv_crosses has a row that is similar to today then look to see if various points were crossed.
#     for example, if today's open was slightly below the pivot point, 
#       then look to see if each row had an open value was slightly below the pivot point.
#       if it did, then the total count gets increased by 1
#       if it did, and it also the pivot point was crossed, then total_pivot count gets increased by 1
#       after all the rows have been examined, divide the total # of rows with crosses by the total number of rows to get
#          the chances of the pivot point being crossed.

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
  prior_close_count = 0
  prior_close_cross = 0
  prior_low_count = 0
  prior_low_cross = 0
  
  range_crosses = [0, 0,0,0,0,0,0,0,0,0,0,0]
  # skip most recent - should be at least look forward days.
  hi_pt = distance_20s(csv_crosses, :yesterday_high_distance, days_back)
  low_pt = distance_20s(csv_crosses, :yesterday_low_distance, days_back)
  close_pt = distance_20s(csv_crosses, :yesterday_close_distance, days_back)
  
  # puts "close"
  # puts close_pt
  
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
    
  #  puts   "prior high = #{row_prior_high}  #{csv_crosses[i][:stockopen]} #{csv_crosses[i+1][:stockhigh]} #{csv_crosses[i][:median_range]} #{open_prior_high}"
     
    if hi_pt[:low] <= csv_crosses[i][:yesterday_high_distance] and csv_crosses[i][:yesterday_high_distance] <= hi_pt[:hi] 
      prior_high_count += 1
      prior_high_cross += csv_crosses[i][:yesterday_high_cross]
    end
   
    if low_pt[:low] <= csv_crosses[i][:yesterday_low_distance] and csv_crosses[i][:yesterday_low_distance] <= low_pt[:hi] 
      prior_low_count += 1
      prior_low_cross += csv_crosses[i][:yesterday_low_cross]
    end
    
    if close_pt[:low] <= csv_crosses[i][:yesterday_close_distance] and csv_crosses[i][:yesterday_close_distance] <= close_pt[:hi] 
      prior_close_count += 1
      prior_close_cross += csv_crosses[i][:yesterday_close_cross]
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
       csv_crosses[0].merge!(last_41(csv_crosses,1)) 
  
  # puts prior_close_count, prior_close_cross
   # return a hash of various values to be displayed
  
  { 
  :stockdate_today => csv_crosses[0][:stockdate],
   :stockdate_yesterday => csv_crosses[1][:stockdate],
  :today_pivot_position=> today_pivot_position,
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
:median_25 => csv_crosses[0][:median_25],
:median_75 => csv_crosses[0][:median_75],
:prior_high_count => prior_high_count ,
:prior_high_cross => prior_high_cross,
:prior_close_count => prior_close_count ,
:prior_close_cross => prior_close_cross,
:prior_low_count => prior_low_count ,
:prior_low_cross => prior_low_cross,
:last_41_u_25 => csv_crosses[0][:last_41_u_25],
:last_41_l_25 => csv_crosses[0][:last_41_l_25] 

}
end
#
# calculate pivot values
#
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
# calculate high, low over past 'days'

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
#
# see where the opening price in the s2 / s1 / pivot / r1 / r2
# further subdivide s1/pivot and pivot/r1 into 4 parts, as these are the most common open positions
#

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
# find the median range (day high - day low) over the past 10 days and 40 days.

def median_range(csv, i)
  a = []
  10.times { | whch | a << csv[i+whch+1][:range] if csv[i+whch+1] }
  a.sort!
  a_length = a.length 
  
  b = []
  40.times { | whch | b  << csv[i+whch+1][:range] if csv[i+whch+1] }
  b.sort!
  b_length = b.length
  if a_length < 4  
    return {:median_range => a[0], :median_25 => a[0], :median_75 => a[a_length-1], :median_long_range => b[0] } 
  end
 
  { :median_range => (a[a_length/2]+a[a_length/2-1])/2.0, :median_25 => (a[a_length/4-1]+a[a_length/4])/2.0, 
  :median_75 => ( a[a_length*3/4] + a[a_length*3/4-1]) / 2.0, :median_long_range => (b[b_length/2]+b[b_length/2-1])/2.0 }
end
# using the last 41 days, sort the high-open/median range values, choose the 10th range value, compute value for 75% reached.

def last_41(csv, start) 
  u = []
  d = []
  u = (start..(start+40)).map { |i| (csv[i][:stockhigh]-csv[i][:stockopen])/csv[i][:median_long_range] }
  d = (start..(start+40)).map { |i| (csv[i][:stockopen]-csv[i][:stocklow])/csv[i][:median_long_range] }
  u.sort!
  d.sort!
  # puts ":median_range = #{  csv[1][:median_long_range] } u[5]= #{u[5]} d[5] = #{d[5]}"
  { :last_41_u_25 => (csv[0][:stockopen] + (u[10] * csv[1][:median_long_range])).round(2) , 
  :last_41_l_25 => (csv[0][:stockopen]  - (d[10] * csv[1][:median_long_range])).round(2) }
end
#
#  take csv and sort values for particular symbol (eg :yesterday_high_distance)
#    find today's value for the symbol in the sorted array (record index position)
#    now find the values +/- csv.length/20 
#  for example, we are looking for :distance_high, and csv array had 1000 items, 
#     then sort the csv array by :distance_high values
#    look for today's :distance_high value (call it today_distance_high_index)
#       now look at sorted array - 50 items to sorted array + 50 items
#       now return those values.
# that way, you are more likely to get around 1/10 of the total csv value to calculate the percentages.

def distance_20s(csv, symbol, daysback)
  return nil if csv.length < 20
  a = []
  (csv.length - daysback).times { |i| a << csv[i][symbol] }
  a.sort!
  find = a.index(csv[0][symbol])
  a_length = a.length
  a20_length = a_length / 20
  if find < a20_length
    first = a[0]
    last = a[a20_length - 1]
  elsif find + a20_length >= a_length
    first = a[a_length - a20_length ]
    last = a[a_length - 1]
  else
    first = a[find - a20_length/2]
    last = a[find + a20_length / 2 ]
  end
  # puts "distance #{last} #{first} #{find} #{a_length} #{a20_length} #{symbol} "
  { :hi => last, :low=>first }  
end

end
