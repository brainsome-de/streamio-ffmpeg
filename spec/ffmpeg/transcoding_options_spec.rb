require 'spec_helper.rb'

module FFMPEG
  describe TranscodingOptions do
    
    context "the #evenize method" do
      
      def evenize(number)
        @movie = Movie.new("#{fixture_path}/movies/sideways movie.mov")
        t = TranscodingOptions.new(@movie)
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