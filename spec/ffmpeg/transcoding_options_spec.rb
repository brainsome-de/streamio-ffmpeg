require 'spec_helper.rb'

module FFMPEG
  describe TranscodingOptions do

    # the video's resolution is 320x180.
    let(:movie) { Movie.new("#{fixture_path}/movies/awesome_widescreen.mov") }

    describe "transcoding" do
      context "with aspect ratio preservation" do
        it "should work on width" do
          original_transcoding_options = {:preserve_aspect_ratio => :width}
          encoding_options = EncodingOptions.new({:resolution => "320x240"})

          options = TranscodingOptions.new(movie, encoding_options, original_transcoding_options)
          options.should == {:resolution => "320x180"}
        end
      end
    end

    describe "Rounding calculated resolution values" do
      
      def calculated_resolution_for(original_resolution, original_transcoding_options)
        encoding_options = EncodingOptions.new({:resolution => original_resolution})      
        options = TranscodingOptions.new(
          movie, 
          encoding_options, 
          original_transcoding_options
        )
        options[:resolution]
      end
      
      context "when calculating the new height" do
        it "rounds down when required" do
          # the original video is 320x180, the exact calculated width is 168.75
          calculated_resolution_for("300x42", :preserve_aspect_ratio => :width).should == "300x168"
        end
        it "rounds up when required" do
          # the original video is 320x180, the exact calculated width is 169.31
          calculated_resolution_for("301x42", :preserve_aspect_ratio => :width).should == "301x170"
        end
      end
      
      context "when calculating the new width" do
        it "rounds down when required" do
          # 177.77
          calculated_resolution_for("42x100", :preserve_aspect_ratio => :height).should == "178x100"
        end
        it "rounds up when required" do
          # 179.55
          calculated_resolution_for("42x101", :preserve_aspect_ratio => :height).should == "180x101"
        end
      end
    end

  end
end