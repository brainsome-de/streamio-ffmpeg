require 'open3'
require 'shellwords'

module FFMPEG
  
  #
  # transcoding options:
  # - preserve_aspect_ratio: [:width|:height]
  # - scale_and_enlarge: boolean, default: true 
  # - autorotate: boolean
  #
  class Transcoder

    @@timeout = 200

    def self.timeout=(time)
      @@timeout = time
    end

    def self.timeout
      @@timeout
    end

    def initialize(movie, output_file, encoding_options = EncodingOptions.new, transcoding_options = {:enlarge => true})
      @movie = movie
      @output_file = output_file
      @encoding_options = encoding_options
      validate_encoding_options!
      @transcoding_options = transcoding_options
      @errors = []
    end

    def validate_encoding_options!
      valid_types = [EncodingOptions, Hash, String]
      unless valid_types.any? { |type| @encoding_options.is_a?(type) }
        msg = "Unknown encoding_options format '#{@encoding_options.class}', should be either #{valid_types.join(', ')}."
        raise ArgumentError, msg
      end
    end
    
    # these are the command line options that get passed to the ffmpeg shell call.
    def raw_options
      # handle EncodingOptions
      options = if @encoding_options.is_a?(String) || @encoding_options.is_a?(EncodingOptions)
        @encoding_options
      else
        EncodingOptions.new(@encoding_options)
      end
      # handle TranscodingOptions
      # I believe transcoding_options can't have worked when @raw_options was a String ...
      if options.is_a?(Hash)
        options.merge!(TranscodingOptions.new(@movie, options, @transcoding_options))
      end
      options
    end
    
    # ffmpeg <  0.8: frame=  413 fps= 48 q=31.0 size=    2139kB time=16.52 bitrate=1060.6kbits/s
    # ffmpeg >= 0.8: frame= 4855 fps= 46 q=31.0 size=   45306kB time=00:02:42.28 bitrate=2287.0kbits/
    def run
      command = "#{FFMPEG.ffmpeg_binary} -y -i #{Shellwords.escape(@movie.path)} #{raw_options} #{Shellwords.escape(@output_file)}"
      FFMPEG.logger.info("Running transcoding...\n#{command}\n")
      output = ""
      last_output = nil
      Open3.popen3(command) do |stdin, stdout, stderr, wait_thr|
        begin
          yield(0.0) if block_given?
          next_line = Proc.new do |line|
            fix_encoding(line)
            output << line
            if line.include?("time=")
              if line =~ /time=(\d+):(\d+):(\d+.\d+)/ # ffmpeg 0.8 and above style
                time = ($1.to_i * 3600) + ($2.to_i * 60) + $3.to_f
              elsif line =~ /time=(\d+.\d+)/ # ffmpeg 0.7 and below style
                time = $1.to_f
              else # better make sure it wont blow up in case of unexpected output
                time = 0.0
              end
              progress = time / @movie.duration
              yield(progress) if block_given?
            end
            if line =~ /Unsupported codec/
              FFMPEG.logger.error "Failed encoding...\nCommand\n#{command}\nOutput\n#{output}\n"
              raise "Failed encoding: #{line}"
            end
          end
          
          if @@timeout
            stderr.each_with_timeout(wait_thr.pid, @@timeout, "r", &next_line)
          else
            stderr.each("r", &next_line)
          end
            
        rescue Timeout::Error => e
          FFMPEG.logger.error "Process hung...\nCommand\n#{command}\nOutput\n#{output}\n"
          raise FFMPEG::Error, "Process hung. Full output: #{output}"
        end
      end

      if encoding_succeeded?
        yield(1.0) if block_given?
        FFMPEG.logger.info "Transcoding of #{@movie.path} to #{@output_file} succeeded\n"
      else
        errors = "Errors: #{@errors.join(", ")}. "
        FFMPEG.logger.error "Failed encoding...\n#{command}\n\n#{output}\n#{errors}\n"
        raise FFMPEG::Error, "Failed encoding.#{errors}Full output: #{output}"
      end
      
      encoded
    end
    
    def encoding_succeeded?
      @errors << "no output file created" and return false unless File.exists?(@output_file)
      @errors << "encoded file is invalid" and return false unless encoded.valid?
      true
    end
    
    def encoded
      @encoded ||= Movie.new(@output_file)
    end
    
    private

    def fix_encoding(output)
      output[/test/]
    rescue ArgumentError
      output.force_encoding("ISO-8859-1")
    end
    
  end

end
