# StreamFromNamedPipe

# Monkey-patches send_file to:
# * allow reading from path when path is a named pipe
# * work in situations when Content-Length can't be determined in advance
# TODO: in the future we should use chunked transfer encoding

module ActionController
  module Streaming

    protected

      def send_file(path, options = {}) #:doc:
        raise MissingFile, "Cannot read file #{path}" unless File.readable?(path)

        options[:length]   ||= File.size(path)
        options[:filename] ||= File.basename(path) unless options[:url_based_filename]
        send_file_headers! options

        @performed_render = false

        if options[:x_sendfile]
          logger.info "Sending #{X_SENDFILE_HEADER} header #{path}" if logger
          head options[:status], X_SENDFILE_HEADER => path
        else
          if options[:stream]
            render :status => options[:status], :text => Proc.new { |response, output|
              logger.info "Streaming file #{path}" unless logger.nil?
              len = options[:buffer_size] || 4096
              File.open(path, 'rb') do |file|
                while buf = file.read(len)
                  output.write(buf)
                end
              end
            }
          else
            logger.info "Sending file #{path}" unless logger.nil?
            File.open(path, 'rb') { |file| render :status => options[:status], :text => file.read }
          end
        end
      end

    private

      def send_file_headers!(options)
        options.update(DEFAULT_SEND_FILE_OPTIONS.merge(options))
        [:length, :type, :disposition].each do |arg|
          raise ArgumentError, ":#{arg} option required" if options[arg].nil?
        end

        disposition = options[:disposition].dup || 'attachment'

        disposition <<= %(; filename="#{options[:filename]}") if options[:filename]

        content_type = options[:type]
        if content_type.is_a?(Symbol)
          raise ArgumentError, "Unknown MIME type #{options[:type]}" unless Mime::EXTENSION_LOOKUP.has_key?(content_type.to_s)
          content_type = Mime::Type.lookup_by_extension(content_type.to_s)
        end
        content_type = content_type.to_s.strip # fixes a problem with extra '\r' with some browsers

        file_headers = {
          'Content-Type'              => content_type,
          'Content-Disposition'       => disposition,
          'Content-Transfer-Encoding' => 'binary'
        }
        file_headers['Content-Length'] = options[:length] if options[:length] > 0
        headers.merge!( file_headers )

        # Fix a problem with IE 6.0 on opening downloaded files:
        # If Cache-Control: no-cache is set (which Rails does by default),
        # IE removes the file it just downloaded from its cache immediately
        # after it displays the "open/save" dialog, which means that if you
        # hit "open" the file isn't there anymore when the application that
        # is called for handling the download is run, so let's workaround that
        headers['Cache-Control'] = 'private' if headers['Cache-Control'] == 'no-cache'
      end

  end
end
