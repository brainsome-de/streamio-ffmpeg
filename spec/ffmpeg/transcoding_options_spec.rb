require 'spec_helper.rb'

module FFMPEG
  describe TranscodingOptions do

   let(:movie) { Movie.new("#{fixture_path}/movies/awesome_widescreen.mov") }
   
    describe "transcoding" do
      context "with aspect ratio preservation" do
        it "should work on width (only TranscodingOptions)" do
          transcoding_options = {:preserve_aspect_ratio => :width}
          encoding_options = EncodingOptions.new({:resolution => "320x240"})
          
          options = TranscodingOptions.new(movie, encoding_options, transcoding_options)
          options.should == {:resolution => "320x180"}
        end
      end
    end

    context "the #evenize method" do
      
      before(:all) do
        movie = Movie.new("#{fixture_path}/movies/sideways movie.mov")
        @transcoding_options = TranscodingOptions.new(movie)
      end
      
      def evenize(number)
        @transcoding_options.send(:evenize, number)
      end
      
      it { evenize(2.2).should == 2 }
      it { evenize(3.2).should == 4 }
      it { evenize(0.2).should == 0 }
      it { evenize(42).should == 42 }
      it { evenize(43).should == 44 }
    end
    
  end
end