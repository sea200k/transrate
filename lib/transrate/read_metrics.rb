module Transrate

  class ReadMetrics

    def initialize assembly
      @assembly = assembly
      @mapper = Bowtie2.new
      self.initial_values
    end

    def run left, right, insertsize=200, insertsd=50
      @mapper.build_index @assembly.file
      samfile = @mapper.map_reads(@assembly.file, 
                                  left, right, 
                                  insertsize, insertsd)
      self.analyse_read_mappings(samfile, insertsize, insertsd)
      {
        :total_mappings => @total,
        :good_mappings => @good,
        :bad_mappings => @bad,
        :both_mapped => @both_mapped,
        :properly_paired => @properly_paired,
        :improper_paired => @improperly_paired,
        :proper_orientation => @proper_orientation,
        :improper_orientation => @improper_orientation,
        :same_contig => @same_contig,
        :realistic_overlap => @realistic_overlap,
        :unrealistic_overlap => @unrealistic_overlap,
        :realistic_fragment => @realistic_fragment,
        :unrealistic_fragment => @unrealistic_fragment,
        :potential_bridges => @supported_bridges
      }
    end

    def analyse_read_mappings samfile, insertsize, insertsd, bridge=true
      @bridges = {} if bridge
      realistic_dist = self.realistic_distance(insertsize, insertsd)
      if File.exists?(samfile) && File.size(samfile) > 0
        ls = BetterSam.new
        rs = BetterSam.new
        sam = File.open(samfile).each_line
        sam.each_slice(2) do |l, r|
          if (l && r) && (ls.parse_line(l) && rs.parse_line(r))
            self.check_read_pair(ls, rs, realistic_dist)
          end
        end
        self.check_bridges if bridge
      else
        raise "samfile #{samfile} not found"
      end
    end

    def initial_values
      @total = 0
      @good = 0
      @bad = 0
      @both_mapped = 0
      @properly_paired = 0
      @improperly_paired = 0
      @proper_orientation = 0
      @improper_orientation = 0
      @same_contig = 0
      @realistic_overlap = 0
      @unrealistic_overlap = 0
      @realistic_fragment = 0
      @unrealistic_fragment = 0
    end

    def realistic_distance insertsize, insertsd
      insertsize + (3 * insertsd)
    end

    def check_read_pair ls, rs, realistic_dist
      return unless ls.primary_aln?
      @total += 1
      if ls.both_mapped?
        # reads are paired
        @both_mapped += 1
        if ls.read_properly_paired?
          # mapped in proper pair
          @properly_paired += 1
          self.check_orientation(ls, rs)
        else
          # not mapped in proper pair
          @improperly_paired += 1
          if ls.chrom == rs.chrom
            # both on same contig
            @same_contig += 1
            self.check_overlap_plausibility(ls, rs)
          else
            self.check_fragment_plausibility(ls, rs, realistic_dist)
          end
        end
      end
    end

    def check_orientation ls, rs
      if ls.pair_opposite_strands?
        # mates in proper orientation
        @proper_orientation += 1
        @good += 1
      else
        # mates in wrong orientation
        @improper_orientation += 1
        @bad += 1
      end
    end

    def check_overlap_plausibility ls, rs
      if Math.sqrt((ls.pos - rs.pos) ** 2) < ls.seq.length
        # overlap is realistic
        @realistic_overlap += 1
        self.check_orientation(ls, rs)
      else
        # overlap not realistic
        @unrealistic_overlap+= 1
        @bad += 1
      end
    end

    def check_fragment_plausibility ls, rs, realistic_dist
      # mates on different contigs
      # are the mapping positions within a realistic distance of
      # the ends of contigs?
      ldist = [ls.pos, ls.seq.length - ls.pos].min
      rdist = [rs.pos, rs.seq.length - rs.pos].min
      if ldist + rdist <= realistic_dist
        # increase the evidence for this bridge
        key = [ls.chrom, rs.chrom].sort.join("<>").to_sym
        if @bridges.has_key? key
          @bridges[key] += 1
        else
          @bridges[key] = 1
        end
        @realistic_fragment += 1
        @good += 1
      else
        @unrealistic_fragment += 1
        @bad += 1
      end
    end

    def check_bridges
      @supported_bridges = 0
      CSV.open('supported_bridges.csv', 'w') do |f|
        @bridges.each_pair do |b, count|
          start, finish = b.to_s.split('<>')
          if count > 1
            f << [start, finish, count]
            @supported_bridges += 1
          end
        end
      end
    end

  end # ReadMetrics

end # Transrate