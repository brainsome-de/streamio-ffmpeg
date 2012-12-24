module FFMPEG
  class TranscodingOptions < Hash
    def initialize(movie, raw_options = {}, options = {})
      @movie = movie
      @raw_options = raw_options
      @original_transcoding_options = options
      generate_raw_options!
    end

    private
    
    def generate_raw_options!
      add_options_for_autorotate if autorotating?
      add_options_for_aspect_ratio if preserve_aspect_ratio?
    end
    
    AUTOROTATION_FILTERS = {
      90  => 'transpose=1',
      180 => 'hflip,vflip',
      270 => 'transpose=2'
    }
    
    def add_options_for_autorotate
      self[:video_filter] = AUTOROTATION_FILTERS[@movie.rotation]
      # also remove the rotation information from the video stream so rotation-aware players don't rotate twice
      self[:metadata]     = 's:v:0 rotate=0'
    end

    def preserve_aspect_ratio?
      @movie.calculated_aspect_ratio && [:width, :height].include?(@original_transcoding_options[:preserve_aspect_ratio])
    end

    # Scaling with autorotation 
    #
    # If scaled in conjuction with autorotation 
    # and the rotation results in an orientation change
    # we must "invert" the side that is preserved
    # as scaling takes place prior to rotation
    #
    # Example: 
    #
    # Original: resolution => 640x480, rotation => 90 
    # Requested: resolution => 660x2, preserved_aspect_ration => :width, autorotate => true
    #
    # => the orientation will change from landscape to portrait
    # => we have to invert the preserved_aspect_ration => :height
    #
    # Expected Output: resolution => 660x880
    #
    # Required Encoding (ffmpeg version < 1.0, scales before rotating, not implemented): resolution => 880x660
    # Required Encoding (ffmpeg version == 1.0, rotates before scaling, this implementation): resolution => 660x880
    #
    def add_options_for_aspect_ratio
      side_to_preserve = @original_transcoding_options[:preserve_aspect_ratio] # the value can be either :width or :height
      new_size = @raw_options.send(side_to_preserve)
      side_to_preserve = invert_side(side_to_preserve) if movie_changes_orientation?

      if @original_transcoding_options[:enlarge] == false
        original_size = @movie.send(side_to_preserve)
        new_size = original_size if original_size < new_size
      end

      case side_to_preserve
      when :width
        new_height = new_size / @movie.calculated_aspect_ratio
        new_height = evenize(new_height)
        self[:resolution] = "#{new_size}x#{new_height}"
      when :height
        new_width = new_size * @movie.calculated_aspect_ratio
        new_width = evenize(new_width)
        self[:resolution] = "#{new_width}x#{new_size}"
      end

      self[:resolution] = invert_resolution(self[:resolution]) if movie_changes_orientation?
    end

    def invert_side(side)
      side == :height ? :width : :height
    end

    # input: WWWxHHH; output: HHH:WWW
    def invert_resolution(resolution)
      resolution.split("x").reverse.join("x")
    end
    
    # ffmpeg requires full, even numbers for its resolution string -- this method ensures that
    def evenize(number)
      number = number.ceil.even? ? number.ceil : number.floor
      number.odd? ? number += 1 : number # needed if new_height ended up with no decimals in the first place
    end
    
    # are we autorotating the movie?
    def autorotating?
      @original_transcoding_options[:autorotate] && @movie.rotation && @movie.rotation != 0
    end
    
    # we need to know if orientation changes when we scale
    def movie_changes_orientation?
      autorotating? && [90, 270].include?(@movie.rotation)
    end

  end
end