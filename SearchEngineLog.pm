package Apache::SearchEngineLog;
# Logging of terms used in searchengines

require 5.005;
use strict;
use warnings;

use Apache;
use Apache::Log;
use DBI;

use vars qw#$SERVER $REGEXEN $DBH $STH#;

our $VERSION = '0.20';

return 1 if $0 eq 'test.pl';

init ();

return 1;

sub handler
{
	my $r = shift or return undef;
	my %h = $r->headers_in ();
	my $l = $r->log ();

	$l->debug ("Apache::SearchEngineLog: entering handle()");

	# first step: check for a (valid and usfull) referer
	unless (defined $h{'Referer'})
	{
		return 1;
	}

	my $referer = $h{'Referer'};

	my ($server, $params);
	# referers are always http.. prove me wrong if i should be..
	if ($referer =~ m#^http://([^/]+)/[^\?]+\?(.+)$#)
	{
		$server = $1;
		$params = $2;
	}
	else
	{
		return 1;
	}

	# referer looks fairly usefull.. let's check this..
	my %params; # i know some people don't like this.. I do ;)
	foreach (split (m#\&#, $params))
	{
		my ($key, $value) = split (m#=#, $_);
		$value =~ y#+# #;
		$value =~ s#%([a-fA-F0-9]{2})#pack ("C", hex ($1))#eg;

		$params{$key} = $value;
	}

	my $field;
	if (!defined $SERVER->{$server})
	{
		# servers without an apropriate entry in $REGEXEN should
		# leave us here..
		$field = check_regexen ($server) or return 1;

		if (defined $params{$field})
		{
			$SERVER->{$server} = $field;

			my $sth = $DBH->prepare ("INSERT INTO config (domain, field) VALUES (?, ?)");
			$sth->execute ($server, $field);
			$sth->finish ();

			$l->info ("Apache::SearchEngineLog: Added new domain: $server");
		}
	}
	else
	{
		$field = $SERVER->{$server};
	}

	unless (defined $params{$field})
	{
		$l->info ("Apache::SearchEngineLog: Known server missing field: $server");
		return 1;
	}

	# ignore goggle's cache-parameters
	if ($params{$field} =~ m#^cache:\S+\s#)
	{
		$params{$field} = $';
	}

	my $uri = $r->uri ();
	my $virtual = '';
	my $s = $r->server ();

	$virtual = $s->server_hostname ();

	my @terms = ();
	foreach my $term (split (m#\s+#, $params{$field}))
	{
		$term =~ s#(^\W+)|(\W+$)##g;
		push (@terms, $term);
	}

	$l->debug ("Apache::SearchEngineLog: Saving to database");

	db_save ($server, $uri, $virtual, @terms);

	return 1;
}

sub db_save
{
	my $server = shift;
	my $uri = shift;
	my $hostname = shift;

	foreach my $term (@_)
	{
		$STH->execute ($server, $term, $uri, $hostname) or warn $STH->errstr ();
	}

	return 1;
}

sub check_regexen
{
	my $server = shift;
	my $retval = '';

	foreach my $re (keys %$REGEXEN)
	{
		if ($server =~ m#$re#)
		{
			$retval = $REGEXEN->{$re};
			last;
		}
	}

	return $retval;
}

sub init
{
	my $s = Apache->server ();
	my $l = $s->log ();

	$REGEXEN =
	{
		qr#yahoo\.#		=>	'p',
		qr#altavista\.#		=>	'q',
		qr#msn\.#		=>	'q',
		qr#voila\.#		=>	'kw',
		qr#lycos\.#		=>	'query',
		qr#search\.terra\.#	=>	'query',
		qr#google\.(?!yahoo)#	=>	'q',
		qr#alltheweb\.com#	=>	'q',
		qr#netscape\.#		=>	'search',
		qr#northernlight\.#	=>	'qr',
		qr#dmoz\.org#		=>	'search',
		qr#search\.aol\.com#	=>	'query',
		qr#www\.search\.com#	=>	'q',
		qr#askjeeves\.#		=>	'ask',
		qr#hotbot\.#		=>	'mt',
		qr#metacrawler\.#	=>	'general'
	};

	my $db_source = $ENV{'DBI_data_source'} or $l->error ("Apache::SearchEngineLog: DBI_data_source not defined");
	my $db_user   = $ENV{'DBI_username'} or $l->error ("Apache::SearchEngineLog: DBI_username not defined");
	my $db_passwd = $ENV{'DBI_password'} or $l->error ("Apache::SearchEngineLog: DBI_password not defined");
	my $db_table  =	(defined $ENV{'DBI_table'} ? $ENV{'DBI_table'} : 'hits');

	$DBH = DBI->connect ($db_source, $db_user, $db_passwd) or $l->error ('Apache::SearchEngineLog: ' . DBI->errstr ());

	$l->debug ("Apache::SearchEngineLog: Database connection established");

	$STH = $DBH->prepare ("INSERT INTO $db_table (date, domain, term, uri, vhost) VALUES (NOW(), ?, ?, ?, ?)") or $l->error ($DBH->errstr ());

	Apache->server->register_cleanup (\&cleanup);

	$SERVER = {};

	# load known servers from database.. this is mostly to speed up
	# recognition later on..
	my $sth = $DBH->prepare ("SELECT domain, field FROM config");
	$sth->execute ();
	while (my ($d, $f) = $sth->fetchrow_array ())
	{
		$SERVER->{$d} = $f;
	}
	$sth->finish ();

	$l->debug ("Apache::SearchEngineLog: init done");

	return 1;
}

sub cleanup
{
	$DBH->disconnect ();
}

__END__

=head1 NAME

Apache::SearchEngineLog - Logging of terms used in search engines

=head1 SYNOPSIS

  #in httpd.conf

  PerlSetEnv DBI_data_source  dbi:driver:dsn
  PerlSetEnv DBI_username     username
  PerlSetEnv DBI_password     password
  PerlSetEnv DBI_table        db_table #optional, defaults to "hits"

  PerlModule Apache::SearchEngineLog

  <Location /test>
    PerlLogHandler Apache::SearchEngineLog
  </Location>

=head1 DESCRIPTION

Apache::SearchEngineLog logs the terms used at a search engine into a SQL
Database, making it easy to analyse it and in turn optimize your website.

=head1 TABLE LAYOUT

  The table "hits" should look somewhat like this:

  +--------+-------------+------+-----+---------------------+-------+
  | Field  | Type        | Null | Key | Default             | Extra |
  +--------+-------------+------+-----+---------------------+-------+
  | term   | varchar(50) |      |     |                     |       |
  | uri    | varchar(50) |      |     |                     |       |
  | domain | varchar(20) |      |     |                     |       |
  | date   | datetime    |      |     | 0000-00-00 00:00:00 |       |
  +--------+-------------+------+-----+---------------------+-------+

  This is the table "config":

  +--------+-------------+------+-----+---------+-------+
  | Field  | Type        | Null | Key | Default | Extra |
  +--------+-------------+------+-----+---------+-------+
  | domain | varchar(20) |      | PRI |         |       |
  | field  | varchar(10) |      |     |         |       |
  +--------+-------------+------+-----+---------+-------+

=head1 SEE ALSO

mod_perl(3), Apache(3)

=head1 AUTHOR

Florian Forster, octopus@verplant.org

=cut