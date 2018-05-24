#!/usr/bin/env perl
use strict;
use warnings;
use autodie;
use Cwd;
use DBI;
use Getopt::Long 'GetOptions';

GetOptions(
  'databank=s' => \my $databank_path,
  'user=s'     => \my $db_user,
  'pass=s'     => \my $db_pass,
) or die "unrecognized arguments passed\n";

die '--databank is required and must be a filepath to a dir'
  unless $databank_path && -d $databank_path;

$db_user //= $ENV{DATABANK_USER};
$db_pass //= $ENV{DATABANK_PASS} || '';
die 'database user must be provided by --user or ENV DATABANK_USER'
  unless defined $db_user;

my $dbh = DBI->connect("DBI:mysql:database=databank;host=localhost",$db_user, $db_pass);
$dbh->do('SET SESSION character_set_client=utf8');
$dbh->do('SET SESSION character_set_connection=utf8');
$dbh->do('SET SESSION character_set_results=utf8');

my $tmp_path ;
while (my $csv_path = <$databank_path*csv>) {
  next unless $csv_path =~ /csv$/;
  my $line_count = -1; # first row is field names
  $tmp_path = cwd() . "/tmp";
  $csv_path =~ m/([^\/]+?)\.csv/;
  my $table = lc $1;

  open my $in, '<', $csv_path;
  open my $out,'>', $tmp_path;
  while (my $line = <$in>) {
    $line =~ s/(?<=,)(?=,|$)/\\N/g;
    print $out $line;
    $line_count++;
  }
  close $in;
  close $out;

  print STDERR "loading: $csv_path into $table\n";
  $dbh->do(qq{
    LOAD DATA LOCAL INFILE '$tmp_path'
    INTO TABLE $table
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n'
    IGNORE 1 LINES
  });

  # check we loaded all the data
  my $sth = $dbh->prepare("select count(1) from $table");
  $sth->execute();
  my $row_count = $sth->fetchrow_arrayref->[0];

  unless ($line_count == $row_count) {
    warn sprintf 'error loading %d lines', $line_count - $row_count;
    print STDERR "warning count: $dbh->{mysql_warning_count}\n";
    my $errh = $dbh->prepare('show warnings');
    $errh->execute();
    while (my $r = $errh->fetchrow_hashref) {
      print STDERR "$r->{Message}\n";
    }
  }
}

END { unlink $tmp_path }
