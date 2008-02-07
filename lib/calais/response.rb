module Calais
  class Response
    attr_reader :rdf, :names, :relationships, :error
    
    def initialize(raw, error=nil)
      @error = error
      @names = []
      @relationships = []

      parse_rdf(raw)
      return if @error

      h_doc = Hpricot.XML(@rdf)
      document_node = h_doc.root.search("//rdf:Description//c:document//..").remove.first
      signature_node = h_doc.root.search("//rdf:Description//c:signature//..").remove.first
      language_node = h_doc.root.search("//rdf:Description//c:lang//..").remove.first
      h_doc = parse_names(h_doc)
      h_doc = parse_relationships(h_doc)
    end
    
    private
      def parse_rdf(raw)
        @rdf = CGI::unescapeHTML Hpricot.XML(raw).at("/string").inner_html
        @hpricot = Hpricot.XML(@rdf)
        @error = Hpricot.XML(response).at("/Error/Exception").inner_html rescue @error
      end
      
      def parse_names(doc)
        name_elements = doc.root.search("//rdf:Description//c:name//..")
        @names = name_elements.map do |ele|
          name = ele.at("c:name").inner_html
          type = ele.at("rdf:type").attributes["rdf:resource"].split("/").last
          hash = ele.attributes["rdf:about"].split("/").last
          
          detection_nodes = doc.root.search("//rdf:Description//c:subject//..").collect! do |ele|
            ele unless ele.at("c:subject").attributes["rdf:resource"].match(hash).nil?
          end.compact
          
          locations = detection_nodes.map do |ele|
            start = ele.at("c:offset").inner_html.to_i
            Range.new(start, start+ele.at("c:length").inner_html.to_i)
          end
          
          detection_nodes.remove
          
          Name.new(
            :name => name,
            :hash => hash,
            :type => type,
            :locations => locations
          )
        end
        name_elements.remove
        
        doc
      end
      
      def parse_relationships(doc)
        relationship_elements = doc.root.search("rdf:Description")
        @relationships = relationship_elements.map do |ele|
          next if ele.at("c:docId")

          hash = ele.attributes["rdf:about"].split("/").last
          type = ele.at("rdf:type").attributes["rdf:resource"].split("/").last
          metadata = {}
          ele.children.each do |child|
            next if child.comment? || child.name == "rdf:type"
            
            value = if child.attributes["rdf:resource"]
                Name.find_in_names(child.attributes["rdf:resource"].split("/").last, @names) rescue nil
              else
                child.inner_html.strip
              end
            metadata[child.name.split(":").last] = value
          end
          
          locations = doc.root.search("//rdf:Description//c:docId//..").collect! do |ele|
            ele unless ele.at("c:subject").attributes["rdf:resource"].match(hash).nil?
          end.compact.map do |ele|
            start = ele.at("c:offset").inner_html.to_i
            Range.new(start, start+ele.at("c:length").inner_html.to_i)
          end
          
          Relationship.new(
            :type => type,
            :hash => hash,
            :metadata => metadata,
            :locations => locations
          )
        end.compact
        relationship_elements.remove
        
        doc
      end
  end
end