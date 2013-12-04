# Extension to Native Ruby reader for the GeoIP database
# Added support for netmask() and range_by_ip()
# Created new method to retrieve all available information based on
# the various GeoIP database files that are available
#
# = COPYRIGHT
#
# This version Copyright (C) 2013 Ryan Harris
# Derived from the C version, Copyright (C) 2003 MaxMind LLC
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
# = SYNOPSIS
#
#   require 'geoip_multi'
#   GeoIPMulti.new('/usr/share/GeoIP/').lookup('24.24.24.24')
#
# = DESCRIPTION
#
# GeoIP searches a GeoIP database for a given host or IP address, and
# returns information about the country where the IP address is allocated.
#
# = PREREQUISITES
#
# You need at least the free GeoIP.dat, for which the last known download
# location is <http://www.maxmind.com/download/geoip/database/GeoIP.dat.gz>
# This API requires the file to be decompressed for searching. Other versions
# of this database are available for purchase which contain more detailed
# information, but this information is not returned by this implementation.
# See www.maxmind.com for more information.

gem 'geoip', '>=1.3.3'
require 'geoip'

class GeoIP
  @last_netmask=0

  def netmask (ip)
    seek_netmask(iptonum(ip))
    @last_netmask
  end

  def filename
    @file.path
  end

  def range_by_ip(ip)
  # this is based on the range_by_ip function in Geo::IP::PurePerl
    ipnum = iptonum(ip)
    record=seek_netmask(ipnum)
    mask = 0xffffffff << 32 - @last_netmask
    left_seek_num = ipnum & mask
    right_seek_num = left_seek_num + ( 0xffffffff & ~mask )
    while (left_seek_num !=0 and record == seek_netmask(left_seek_num - 1))
      leftmask = 0xffffffff << 32 - @last_netmask
      left_seek_num = (left_seek_num - 1) & leftmask
    end
    while (right_seek_num != 0xffffffff and record == seek_netmask(right_seek_num + 1))
      rightmask = 0xffffffff << 32 - @last_netmask
      right_seek_num = ( right_seek_num + 1 ) & rightmask
      right_seek_num += (0xffffffff & ~rightmask)
    end
    [numtoip(left_seek_num), numtoip(right_seek_num)]
  end

  private

  def numtoip(ipnum) #:nodoc:
    IPAddr.new(ipnum, Socket::AF_INET).to_s
  end

  def seek_netmask(ipnum) #:nodoc:
    # minor modification of original seek_record() method to include updating @last_netmask
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

end

class GeoIPMulti < GeoIP

  def initialize (*filenames)
    @geoip_databases=[]
    filenames=Dir.glob(File.join(File.expand_path($0)[/(.*\/)/],'*.dat')) if filenames.length == 0
    add_database(filenames)
  end

  def add_database (*filenames)
    filenames.flatten!
    filenames.each do |filename|
      if File.directory?(filename)
        Dir.glob(File.join(filename,'*.dat')) {|filename| @geoip_databases << GeoIP.new(filename)}
      else
        GeoIP.new(filename)
        @geoip_databases << GeoIP.new(filename)
      end
    end
  end

  def lookup(ip)
    results ={}
    @geoip_databases.each do |current_database|
      case current_database.database_type
        #IPv4 addresses expected, IPv6 not currently supported, maybe in the future...
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
