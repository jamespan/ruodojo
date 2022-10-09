require 'digest/md5'

module Jekyll
  module MDhash
    def md5(input)
      return Digest::MD5.hexdigest input.strip
    end
  end
end

Liquid::Template.register_filter(Jekyll::MDhash)
