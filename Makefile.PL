use ExtUtils::MakeMaker;

WriteMakefile
(
	'NAME'		=> 'Apache::SearchEngineLog',
	'AUTHOR'	=> 'Florian Forster <octopus@verplant.org>',
	'ABSTRACT'	=> 'Logging of search terms',
	'VERSION_FROM'	=> 'SearchEngineLog.pm', # finds $VERSION
	'PREREQ_PM'	=> {},
	'PM'		=> {'SearchEngineLog.pm' => '$(INST_LIBDIR)/SearchEngineLog.pm'},
);

print <<EOF;

#################################################################
#                                                               #
#  You need to set up an SQL database with appropriate tables.  #
#    Please read the README for configuration instructions.     #
#                                                               #
#################################################################

EOF
