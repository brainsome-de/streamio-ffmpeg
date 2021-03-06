require 'spec_helper.rb'

module FFMPEG
  describe Transcoder do
    let(:movie) { Movie.new("#{fixture_path}/movies/awesome movie.mov") }
      
    describe "initialization" do
      let(:output_path) { "#{tmp_path}/awesome.flv" }
      
      it "should accept EncodingOptions as options" do
        lambda { Transcoder.new(movie, output_path, EncodingOptions.new) }.should_not raise_error(ArgumentError)
      end
      
      it "should accept Hash as options" do
        lambda { Transcoder.new(movie, output_path, :video_codec => "libx264") }.should_not raise_error(ArgumentError)
      end
      
      it "should accept String as options" do
        lambda { Transcoder.new(movie, output_path, "-vcodec libx264") }.should_not raise_error(ArgumentError)
      end
      
      it "should not accept anything else as options" do
        lambda { Transcoder.new(movie, output_path, ["array?"]) }.should raise_error(ArgumentError, /Unknown options format/)
      end
    end
    
    describe "transcoding" do
      before do
        FFMPEG.logger.should_receive(:info).at_least(:once)
      end
      
      context "when ffmpeg freezes" do
        before do
          @original_timeout = Transcoder.timeout
          @original_ffmpeg_binary = FFMPEG.ffmpeg_binary
          
          Transcoder.timeout = 1
          FFMPEG.ffmpeg_binary = "#{fixture_path}/bin/ffmpeg-hanging"
        end
        
        it "should fail when the timeout is exceeded" do
          FFMPEG.logger.should_receive(:error)
          transcoder = Transcoder.new(movie, "#{tmp_path}/timeout.mp4")
          lambda { transcoder.run }.should raise_error(FFMPEG::Error, /Process hung/)
        end
        
        after do
          Transcoder.timeout = @original_timeout
          FFMPEG.ffmpeg_binary = @original_ffmpeg_binary
        end
      end
      
      context "with timeout disabled" do
        before do
          @original_timeout = Transcoder.timeout
          Transcoder.timeout = false
        end
        
        it "should still work" do
          encoded = Transcoder.new(movie, "#{tmp_path}/awesome.mpg").run
          encoded.resolution.should == "640x480"
        end
        
        after { Transcoder.timeout = @original_timeout }
      end
        
      it "should transcode the movie with progress given an awesome movie" do
        FileUtils.rm_f "#{tmp_path}/awesome.flv"
        
        transcoder = Transcoder.new(movie, "#{tmp_path}/awesome.flv")
        progress_updates = []
        transcoder.run { |progress| progress_updates << progress }
        transcoder.encoded.should be_valid
        progress_updates.should include(0.0, 1.0)
        progress_updates.length.should >= 3
        File.exists?("#{tmp_path}/awesome.flv").should be_true
      end
      
      it "should transcode the movie with EncodingOptions" do
        FileUtils.rm_f "#{tmp_path}/optionalized.mp4"
        
        options = {:video_codec => "libx264", :frame_rate => 10, :resolution => "320x240", :video_bitrate => 300,
                   :audio_codec => "libfaac", :audio_bitrate => 32, :audio_sample_rate => 22050, :audio_channels => 1,
                   :custom => "-flags +mv4+aic -trellis 2 -cmp 2 -subcmp 2 -g 300"}
        
        encoded = Transcoder.new(movie, "#{tmp_path}/optionalized.mp4", options).run
        encoded.video_bitrate.should be_within(10).of(300)
        encoded.video_codec.should =~ /h264/
        encoded.resolution.should == "320x240"
        encoded.frame_rate.should == 10.0
        encoded.audio_bitrate.should be_within(2).of(32)
        encoded.audio_codec.should =~ /aac/
        encoded.audio_sample_rate.should == 22050
        encoded.audio_channels.should == 1
      end
      
      context "with aspect ratio preservation" do
        before do
          @movie = Movie.new("#{fixture_path}/movies/awesome_widescreen.mov")
          @options = {:resolution => "320x240"}
        end
        
        it "should work on width" do
          special_options = {:preserve_aspect_ratio => :width}

          encoded = Transcoder.new(@movie, "#{tmp_path}/preserved_aspect.mp4", @options, special_options).run
          encoded.resolution.should == "320x180"
        end

        it "should work on height" do
          special_options = {:preserve_aspect_ratio => :height}
        
          encoded = Transcoder.new(@movie, "#{tmp_path}/preserved_aspect.mp4", @options, special_options).run
          encoded.resolution.should == "426x240"
        end

        it "should not be used if original resolution is undeterminable" do
          @movie.should_receive(:calculated_aspect_ratio).and_return(nil)
          special_options = {:preserve_aspect_ratio => :height}
          
          encoded = Transcoder.new(@movie, "#{tmp_path}/preserved_aspect.mp4", @options, special_options).run
          encoded.resolution.should == "320x240"
        end
        
        it "should round to resolutions divisible by 2" do
          @movie.should_receive(:calculated_aspect_ratio).at_least(:once).and_return(1.234)
          special_options = {:preserve_aspect_ratio => :width}
          
          encoded = Transcoder.new(@movie, "#{tmp_path}/preserved_aspect.mp4", @options, special_options).run
          encoded.resolution.should == "320x260" # 320 / 1.234 should at first be rounded to 259
        end

        context "enlarged scaling disabled" do

          it "it works to shrink" do
            @options = {:resolution => "160x120"}
            special_options = {:preserve_aspect_ratio => :width, :enlarge => false}
            encoded = Transcoder.new(@movie, "#{tmp_path}/preserved_aspect.mp4", @options, special_options).run
            encoded.resolution.should == "160x90"
          end

          it "it does not to enlarge" do
            special_options = {:preserve_aspect_ratio => :height, :enlarge => false}
            # original resolution: "320x180"
            # target resolution: "320x240"
            # preserved target resolution: "426x240"
            # expected resolution: "320x180", video may not be enlarged
            original_resolution = @movie.resolution   
            encoded = Transcoder.new(@movie, "#{tmp_path}/preserved_aspect.mp4", @options, special_options).run
            encoded.resolution.should == original_resolution 
          end
        end
        
      end

      it "should transcode the movie with String options" do
        FileUtils.rm_f "#{tmp_path}/string_optionalized.flv"
        
        encoded = Transcoder.new(movie, "#{tmp_path}/string_optionalized.flv", "-s 300x200 -ac 2").run
        encoded.resolution.should == "300x200"
        encoded.audio_channels.should == 2
      end
      
      it "should transcode the movie which name include single quotation mark" do
        FileUtils.rm_f "#{tmp_path}/output.flv"
        
        movie = Movie.new("#{fixture_path}/movies/awesome'movie.mov")
        
        lambda { Transcoder.new(movie, "#{tmp_path}/output.flv").run }.should_not raise_error
      end
      
      it "should transcode when output filename includes single quotation mark" do
        FileUtils.rm_f "#{tmp_path}/output with 'quote.flv"
        
        lambda { Transcoder.new(movie, "#{tmp_path}/output with 'quote.flv").run }.should_not raise_error
      end
      
      pending "should not crash on ISO-8859-1 characters (dont know how to spec this)"
      
      it "should fail when given an invalid movie" do
        FFMPEG.logger.should_receive(:error)
        movie = Movie.new(__FILE__)
        transcoder = Transcoder.new(movie, "#{tmp_path}/fail.flv")
        lambda { transcoder.run }.should raise_error(FFMPEG::Error, /no output file created/)
      end
      
      it "should encode to the specified duration if given" do
        encoded = Transcoder.new(movie, "#{tmp_path}/durationalized.mp4", :duration => 2).run
        
        encoded.duration.should >= 1.8
        encoded.duration.should <= 2.2
      end
      
      context "with screenshot option" do
        it "should transcode to original movies resolution by default" do
          encoded = Transcoder.new(movie, "#{tmp_path}/image.jpg", :screenshot => true).run
          encoded.resolution.should == "640x480"
        end
        
        it "should transcode absolute resolution if specified" do
          encoded = Transcoder.new(movie, "#{tmp_path}/image.bmp", :screenshot => true, :seek_time => 3, :resolution => '400x200').run
          encoded.resolution.should == "400x200"
        end
        
        it "should be able to preserve aspect ratio" do
          encoded = Transcoder.new(movie, "#{tmp_path}/image.png", {:screenshot => true, :seek_time => 4, :resolution => '320x500'}, :preserve_aspect_ratio => :width).run
          encoded.resolution.should == "320x240"
        end
      end
    
      context "with autorotation" do
        before do
          @movie = Movie.new("#{fixture_path}/movies/sideways movie.mov")
          @options = {}
        end
        it "shouldn't rotate when autorotate is false" do
          transcoder_options = {:autorotate => false}
          encoded = Transcoder.new(@movie, "#{tmp_path}/autorotated.mp4", @options, transcoder_options).run
          encoded.resolution.should == @movie.resolution
        end
        it "shouldn't rotate when move is not rotated" do
          @movie = Movie.new("#{fixture_path}/movies/awesome_widescreen.mov")
          transcoder_options = {:autorotate => true}
          encoded = Transcoder.new(@movie, "#{tmp_path}/autorotated.mp4", @options, transcoder_options).run
          encoded.resolution.should == @movie.resolution
        end
        it "should reset the autorotate metadata" do
          transcoder_options = {:autorotate => true}
          encoded = Transcoder.new(@movie, "#{tmp_path}/autorotated.mp4", @options, transcoder_options).run
          @movie.rotation.should_not == nil
          encoded.rotation.should == nil
        end
        it "should rotate when move is rotated and autorotate is true" do
          transcoder_options = {:autorotate => true}
          encoded = Transcoder.new(@movie, "#{tmp_path}/autorotated.mp4", @options, transcoder_options).run
          rotated_resolution = @movie.resolution.split('x').reverse.join('x')
          encoded.resolution.should == rotated_resolution
        end
        it "inverts aspect ratio when autorotating" do
          # by default also enlarges the video
          @options = {:resolution => "660x42"}
          transcoder_options = {:autorotate => true, :preserve_aspect_ratio => :width}
          encoded = Transcoder.new(@movie, "#{tmp_path}/autorotated.mp4", @options, transcoder_options).run
          rotated_resolution = @movie.resolution.split('x').reverse.join('x')
          encoded.width.should == 660
          encoded.height.should == 880
        end
        context "enlarged scaling disabled" do

          it "it works to shrink" do
            # original resolution: 640x480
            # original rotated resolution: 480x640
            # target resolution 240x42
            # expected resoltuion: 240x320
            @options = {:resolution => "240x42"}
            special_options = {:autorotate => true, :preserve_aspect_ratio => :width, :enlarge => false}
            encoded = Transcoder.new(@movie, "#{tmp_path}/preserved_aspect.mp4", @options, special_options).run
            encoded.resolution.should == "240x320"
          end

          it "it does not enlarge" do
            @options = {:resolution => "660x42"}
            transcoder_options = {:autorotate => true, :preserve_aspect_ratio => :width, :enlarge => false}
            encoded = Transcoder.new(@movie, "#{tmp_path}/autorotated.mp4", @options, transcoder_options).run
            rotated_resolution = "480x640"
          end
        end
      end
    end
    
    context "the #even method" do
      def evenize(number)
        @movie = Movie.new("#{fixture_path}/movies/sideways movie.mov")
        t = Transcoder.new(@movie, "#{tmp_path}/preserved_aspect.mp4")
        t.send(:evenize, number)
      end
      it { evenize(2.2).should == 2 }
      it { evenize(3.2).should == 4 }
      it { evenize(0.2).should == 0 }
      it { evenize(42).should == 42 }
      it { evenize(43).should == 44 }
    end
  end
end
