Gem::Specification.new do |s|
  # meta
  s.name        = 'GeneValidator'
  s.date        = '2013-07-22'
  s.version     = '0.1'
  s.authors     = ['Monica Dragan', 'Yannick Wurm', 'Anurag Priyam']
  s.email       = 'monica.dragan@cti.pub.ro'
  s.homepage    = 'https://github.com/monicadragan/gene_prediction/'

  s.summary     = 'Identifying problems with gene predictions.'
  s.description = <<DESC
The tool validates the input predicted genes and provides useful information (length validation, gene merge validation, sequence duplication checking, ORF finding) based on the similarities to genes in public databases.
DESC

  # dependencies
  s.required_ruby_version     = '>= 1.9.3'

  s.add_dependency('bio-blastxmlparser')
  s.add_dependency('rinruby')
  s.add_dependency('bio')
  s.add_dependency('mini_shoulda')

  s.files       = ["lib/genevalidator.rb"] + Dir['lib/**/*']
  s.executables   = ['genevalidator', 'get_raw_sequences']

  # post install information
  s.post_install_message = <<INFO

------------------------------------------------------------------------
  Thank you for validating your gene predictions with GeneValidator!

  To launch GeneValidator execute 'genevalidator' from command line.

    $ genevalidatior [-v VALIDATIONS] [--skip_blast xml_file_path] [-s START] fasta_file_path

  This is a GSoC project. 
  Visit https://github.com/monicadragan/gene_prediction/wiki for more information.
------------------------------------------------------------------------

INFO
end
