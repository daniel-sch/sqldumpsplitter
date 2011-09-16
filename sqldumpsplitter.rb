#!/usr/bin/env ruby
#Encoding: UTF-8

require 'optparse'
require 'zlib'

class SqldumpSplitter
  attr_accessor :filename, :filesize, :compression

  class PlainFile
    attr_reader :size

    def initialize(filename)
      @file = open(filename, 'w')
      @size = 0
    end

    def write(text)
      @file.write(text)
      @size += text.length
    end

    def close
      @file.close
    end
  end

  class GzipFile
    def initialize(filename)
      @filename = filename
      @writer = Zlib::GzipWriter.new(open(filename, 'w'))
    end

    def write(text)
      @writer.write(text)
      @writer.flush
    end

    def size
      File.size(@filename)
    end

    def close
      @writer.close
    end
  end

  def open_numbered_file
    basename, extension = @filename.split('.', 2)

    extension.sub!(/\.gz$/, '') unless @compression == :gzip
    extension << '.gz' if compression == :gzip && !extension.end_with?('.gz')

    new_name = "%s-%.2d.%s" % [basename, @filenumber, extension]
    @filenumber += 1
    puts "Opening new file #{new_name}."

    case @compression
    when :plain
      PlainFile.new(new_name)
    when :gzip
      GzipFile.new(new_name)
    end
  end

  def open_file_for_reading
    if @filename.end_with?('.gz')
      Zlib::GzipReader.open(@filename)
    else
      open(@filename)
    end
  end


  def run
    puts "File #{@filename} will be splitted into chunks of maximal #{@filesize} bytes (#{@gzip ? 'compressed':'uncompressed'})."

    @filenumber = 0
    cur_query = ''

    infile = open_file_for_reading
    outfile = open_numbered_file

    infile.each_line do |line|
      next if line.strip.empty? || line.start_with?('--', '/*')

      cur_query << line.strip << "\n"
      if cur_query.end_with?(";\n") then
        if outfile.size + cur_query.length >= filesize then
          outfile.close
          outfile = open_numbered_file
        end

        outfile.write(cur_query)
        cur_query = ''
      end
    end

    infile.close
    outfile.close
  end
end


def print_error(error, opts)
  puts "ERROR: " + error
  puts opts
  exit
end

FACTORS = {
  'KI' => 1024,
  'MI' => 1024*1024,
  'GI' => 1024*1024*1024,
  'K' => 1000,
  'M' => 1000000,
  'G' => 1000000000
}
FILESIZE_PATTERN = /^(\d+\.?\d*)([KMG]I?)?$/

def parse_filesize(s)
  if !match = FILESIZE_PATTERN.match(s.upcase) then
    nil
  else
    (match[1].to_f * FACTORS[match[2]]).to_i
  end
end

splitter = SqldumpSplitter.new
splitter.compression = :plain

opts = OptionParser.new do |o|
  o.banner = "Usage: #{$0} [options]"

  o.on('-f', '--file DUMPFILE', 'File to split (mandatory)') do |filename|
    print_error("file #{filename} can't be read", o) if !File.readable?(filename)
    splitter.filename = filename
  end
  o.on('-s', '--size FILESIZE', 'maximum filesize of output files (mandatory)',
                                'formats accepted are 2.5M for 2.5 Megabytes or 2.5MI for Mebibytes') do |filesize|
    print_error('filesize is invalid', o) if !splitter.filesize = parse_filesize(filesize)
  end
  o.on('-z', '--gzip', 'gzip compression for output files') do
    splitter.compression = :gzip
  end
  o.on('-p', '--plain', 'no compression for output files (default)') do
    splitter.compression = :plain
  end
end
opts.parse!(ARGV)

print_error('no filename given', opts) if splitter.filename.nil?
print_error('no filesize given', opts) if splitter.filesize.nil?

splitter.run
