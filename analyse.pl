#!/usr/bin/perl -w
# analyse.pl
# part of Apache::SearchEngineLog

use strict;
use DBI;
use Getopt::Long;

my $host = 'localhost';
my $db = '';
my $user = (defined $ENV{'USER'} ? $ENV{'USER'} : '');
my $passwd = '';
my $output = '';
my $type = 'mysql';

Getopt::Long::config ('pass_through');
my $result = GetOptions
(
	'host|h=s'	=>	\$host,
	'db|d=s'	=>	\$db,
	'user|u=s'	=>	\$user,
	'password|p=s'	=>	\$passwd,
	'output|o=s'	=>	\$output,
	'type|t=s'	=>	\$type
);

if (!$db or !$user)
{
	die <<EOF;
Usage: $0 --db=<database> [options]

	-h	--host		Host to connect to (default: localhost)
	-d	--db		Name of the database to use (required!)
	-t	--type		Type of the DB (default: mysql)
	-u	--user		User to log into the database
	-p	--password	Password to log into the database
	-o	--output	File to write output to

EOF
}

if ($output)
{
	open (OUT, "> $output") or die $!;
}
else
{
	*OUT = *STDOUT;
}

my $DBH = DBI->connect ("DBI:$type:database=$db;host=$host", $user, $passwd) or die DBI->errstr ();
my $termsth = $DBH->prepare ("SELECT term, count(*) AS cnt FROM hits WHERE uri = ? GROUP BY term ORDER BY cnt DESC");

my $sth = $DBH->prepare ("SELECT uri, count(*) AS cnt FROM hits GROUP BY uri ORDER BY cnt DESC");
$sth->execute () or die $sth->errstr ();

while (my ($uri, $count) = $sth->fetchrow_array ())
{
	print OUT '=' x 75 . "\n";
	print OUT "  $uri  ($count)\n";
	print OUT '-' x 75 . "\n";

	$termsth->execute ($uri) or die $termsth->errstr ();

	while (my ($term, $count) = $termsth->fetchrow_array ())
	{
		my $pad = ' ' x (55 - length ($term));
		print  OUT "  $term$pad  ";
		printf OUT ("%5u\n", $count);
	}

	print OUT "\n";

	$termsth->finish ();
}

$sth->finish ();
$DBH->disconnect ();

if ($output)
{
	close OUT;
}

exit (0);
