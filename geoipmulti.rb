gem 'geoip', '1.3.3'
require 'geoip'

class GeoIP
  @last_netmask=0

  def netmask (ip)
    seek_netmask(iptonum(ip))
    @last_netmask
  end

  def numtoip(ipnum)
    IPAddr.new(ipnum, Socket::AF_INET).to_s
  end

  def filename
    @file.path
  end

  def seek_netmask(ipnum) #:nodoc:
                         # Binary search in the file.
                         # Records are pairs of little-endian integers, each of @record_length.
    offset = 0

    31.downto(0) do |depth|
      off = (@record_length * 2 * offset)
      buf = atomic_read(@record_length * 2, off)

      buf.slice!(0...@record_length) if ((ipnum & (1 << depth)) != 0)
      offset = le_to_ui(buf[0...@record_length].unpack("C*"))

      if (offset >= @database_segments[0])
        @last_netmask = 32 - depth
        return offset
      end
    end
  end

  def range_by_ip(ip)
    ipnum = iptonum(ip)
    record=seek_netmask(ipnum)
    nm=@last_netmask
    m = 0xffffffff << 32 - nm
    left_seek_num = ipnum & m
    right_seek_num = left_seek_num + ( 0xffffffff & ~m )
    while (left_seek_num !=0 and record == seek_netmask(left_seek_num - 1))
      lm = 0xffffffff << 32 - @last_netmask
      left_seek_num = (left_seek_num - 1) & lm
    end
    while (right_seek_num != 0xffffffff and record == seek_netmask(right_seek_num + 1))
      rm = 0xffffffff << 32 - @last_netmask
      right_seek_num = ( right_seek_num + 1 ) & rm
      right_seek_num += (0xffffffff & ~rm)
    end
    [numtoip(left_seek_num), numtoip(right_seek_num)]
  end
end

class GeoIPMulti < GeoIP
  def initialize (*filenames)
    @geoip_databases=[]
    filenames=Dir.glob(File.join(File.dirname(__FILE__),'*.dat')) if filenames.length == 0
    add_database(*filenames)
  end

  def add_database (*filenames)
    filenames.each do |filename|
      if File.directory?(filename)
        Dir.glob(File.join(filename,'*.dat')) {|filename| @geoip_databases << GeoIP.new(filename)}
      else
        @geoip_databases << GeoIP.new(filename)
      end
    end
  end

  def lookup(ip)
    results ={}
    @geoip_databases.each do |current_database|
      case current_database.database_type
        when GEOIP_COUNTRY_EDITION
          results.merge!(current_database.country(ip).to_hash)
        when GEOIP_CITY_EDITION_REV1
          results.merge!(current_database.city(ip).to_hash)
          results.merge!(:netmask=>current_database.netmask(ip))
          iprange = current_database.range_by_ip(ip)
          results.merge!(:first_ip => iprange[0],:last_ip => iprange[1])
        when GEOIP_ISP_EDITION
          results.merge!(:isp=>current_database.isp(ip))
        when GEOIP_ORG_EDITION
          results.merge!(current_database.filename[/([^\/]+)$/][/(?:GeoIP)?([^.]+)/,1].downcase.to_sym => current_database.isp(ip))
        when GEOIP_ASNUM_EDITION
          results.merge!(current_database.asn(ip).to_hash)
        else
          puts "Unknown or Unsupported GeoIP database type:"
          puts "filename:#{current_database.filename} => database_type:#{current_database.database_type}"
      end
    end
    results
  end
end
