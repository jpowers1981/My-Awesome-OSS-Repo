#!/usr/bin/env ruby

require 'genevalidator/sequences'
require 'genevalidator/hsp'
require 'genevalidator/output'
require 'genevalidator/exceptions'
require 'bio-blastxmlparser'
require 'net/http'
require 'open-uri'
require 'uri'
require 'io/console'
require 'yaml'
require 'bio'

class BlastUtils

  EVALUE = 1e-5

  ##
  # Calls blast from standard input with specific parameters
  # Params:
  # +blast_type+: blast command in String format (e.g 'blastx' or 'blastp')
  # +query+: String containing the the query in fasta format
  # +db+: database
  # +num_threads+: The number of threads to run BLAST with. 
  # +gapopen+: gapopen blast parameter
  # +gapextend+: gapextend blast parameter
  # +nr_hits+: max number of hits
  # Output:
  # String with the blast xml output
  def self.call_blast_from_stdin(blast_type, query, db, num_threads, gapopen=11,
                                 gapextend=1, nr_hits=200)
    # -num_threads is not supported on remote databases, so need to check if
    #   running blast against local db or not 
    if (db !~ /remote/)
      blastcmd = "#{blast_type} -db '#{db}' -evalue #{EVALUE} -outfmt 5" + 
                 " -max_target_seqs #{nr_hits} -gapopen #{gapopen}" +
                 " -gapextend #{gapextend} -num_threads #{num_threads}"
    else
      blastcmd = "#{blast_type} -db '#{db}' -evalue #{EVALUE} -outfmt 5" +
                 " -max_target_seqs #{nr_hits} -gapopen #{gapopen}" +
                 " -gapextend #{gapextend}"
    end

    cmd = "echo \"#{query}\" | #{blastcmd}"
    %x[#{cmd} 2>/dev/null]
  end

  ##
  # Runs BLAST on an input file
  # Params:
  # +blast_type+: blast command in String format (e.g 'blastx' or 'blastp')
  # +query_file+: Input file
  # +opt+: Hash containing the following ids: :blast_xml_file, :db, :num_threads
  # +gapopen+: gapopen blast parameter
  # +gapextend+: gapextend blast parameter
  # +nr_hits+: max number of hits
  # Output:
  # XML file
  def self.run_blast_on_file(query_file, opt, gapopen=11, gapextend=1,
                             nr_hits=200)
    seq_type   = guess_sequence_type_from_file(query_file)
    blast_type = (seq_type == :protein) ? 'blastp' : 'blastx'

    if (opt[:db] !~ /remote/)
      blastcmd = "#{blast_type} -query '#{query_file}'" +
                 " -out '#{opt[:blast_xml_file]}' -db #{opt[:db]} " +
                 " -evalue #{EVALUE} -outfmt 5 -max_target_seqs #{nr_hits}" +
                 " -gapopen #{gapopen} -gapextend #{gapextend}" +
                 " -num_threads #{opt[:num_threads]}"
    else
      blastcmd = "#{blast_type} -query '#{query_file}'" +
                 " -out '#{opt[:blast_xml_file]}' -db #{opt[:db]}" +
                 " -evalue #{EVALUE} -outfmt 5 -max_target_seqs #{nr_hits}" +
                 " -gapopen #{gapopen} -gapextend #{gapextend}"
    end

    %x[#{blastcmd}]
    if File.zero?(opt[:blast_xml_file])
      puts "Blast failed to run on the input file. Please ensure that the"
      puts "BLAST database exists and try again"
      exit 1
    end
  end

  ##
  # Parses the next query from the blast xml output query
  # Params:
  # +iterator+: blast xml iterator for hits
  # +type+: the type of the sequence: :nucleotide or :protein
  # Outputs:
  # Array of +Sequence+ objects corresponding to the list of hits
  def self.parse_next_query_xml(iterator, type)
    begin
      raise TypeError unless iterator.is_a? Enumerator

      hits = Array.new
      iter = iterator.next

      # parse blast the xml output and get the hits
      # hits obtained are proteins! (we use only blastp and blastx)
      iter.each do | hit |

        seq = Sequence.new

        seq.length_protein = hit.len.to_i
        seq.type           = :protein
        seq.identifier     = hit.hit_id
        seq.definition     = hit.hit_def
        #puts seq.identifier
        seq.accession_no = hit.accession

        # get all high-scoring segment pairs (hsp)
        hsps = []

        hit.hsps.each do |hsp|
          current_hsp            = Hsp.new
          current_hsp.hsp_evalue = hsp.evalue.to_i

          current_hsp.hit_from         = hsp.hit_from.to_i
          current_hsp.hit_to           = hsp.hit_to.to_i
          current_hsp.match_query_from = hsp.query_from.to_i
          current_hsp.match_query_to   = hsp.query_to.to_i

          if type == :nucleotide
            current_hsp.match_query_from =  (current_hsp.match_query_from / 3) + 1
            current_hsp.match_query_to   =  (current_hsp.match_query_to / 3) + 1
          end

          current_hsp.query_reading_frame = hsp.query_frame.to_i

          current_hsp.hit_alignment = hsp.hseq.to_s
          if BlastUtils.guess_sequence_type(current_hsp.hit_alignment) != :protein
            raise SequenceTypeError
          end

          current_hsp.query_alignment = hsp.qseq.to_s
          if BlastUtils.guess_sequence_type(current_hsp.query_alignment) != :protein
            raise SequenceTypeError
          end
          current_hsp.align_len = hsp.align_len.to_i
          current_hsp.identity  = hsp.identity.to_i
          current_hsp.pidentity = 100 * hsp.identity / (hsp.align_len + 0.0)

          hsps.push(current_hsp)
        end

        seq.hsp_list = hsps
        hits.push(seq)
      end

      return hits

    rescue TypeError => error
      $stderr.print "Type error at #{error.backtrace[0].scan(/\/([^\/]+:\d+):.*/)[0][0]}. "<<
        "Possible cause: you didn't call parse method first!\n"
      exit 1
    rescue SequenceTypeError => error
      $stderr.print "Sequence Type error at #{error.backtrace[0].scan(/\/([^\/]+:\d+):.*/)[0][0]}. "<<
        "Possible cause: the blast output was not obtained against a protein database.\n"
      exit 1
    rescue StopIteration
      nil
    end
  end

  ##
  # Strips all non-letter characters. guestimates sequence based on that.
  # If less than 10 useable characters... returns nil
  # If more than 90% ACGTU returns :nucleotide. else returns :protein
  # Params:
  # +sequence_string+: String to validate
  # Output:
  # nil, :nucleotide or :protein
  def self.guess_sequence_type(sequence_string)
    # removing non-letter and ambiguous characters
    cleaned_sequence = sequence_string.gsub(/[^A-Z]|[NX]/i, '')
    return nil if cleaned_sequence.length < 10 # conservative

    type = Bio::Sequence.new(cleaned_sequence).guess(0.9)
    (type == Bio::Sequence::NA) ? :nucleotide : :protein
  end

  def self.guess_sequence_type_from_file(file)
    lines = File.foreach(file).first(10)
    seqs = ''
    lines.each do |l|
      seqs += l.chomp unless l[0] == '>'
    end
    guess_sequence_type(seqs)
  end

  ##
  # Method copied from sequenceserver/sequencehelpers.rb
  # Splits input at putative fasta definition lines (like ">adsfadsf"), guesses sequence type for each sequence.
  # If not enough sequence to determine, returns nil.
  # If 2 kinds of sequence mixed together, raises ArgumentError
  # Otherwise, returns :nucleotide or :protein
  # Params:
  # +sequence_string+: String to validate
  # Output:
  # nil, :nucleotide or :protein
  def self.type_of_sequences(fasta_format_string)
    # the first sequence does not need to have a fasta definition line
    sequences = fasta_format_string.split(/^>.*$/).delete_if { |seq| seq.empty? }
    # get all sequence types
    sequence_types = sequences.collect { |seq| BlastUtils.guess_sequence_type(seq) }.uniq.compact

    return nil if sequence_types.empty?
    return sequence_types.first if sequence_types.length == 1
    raise SequenceTypeError
  end
end
