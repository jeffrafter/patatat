#!/usr/bin/perl

# $Id: theyoke 34 2007-02-18 18:50:19Z mackers $
# http://www.mackers.com/projects/theyoke/
#
# TheYoke is an ultra-simple RSS aggregrator designed for use on the UNIX command line.

use strict;
use XML::RSS;
use URI;
use LWP::UserAgent;
use Digest::MD5 qw(md5_base64);
use Encode qw(encode_utf8);
use Term::Size;
use Getopt::Long;
use HTML::FormatText;

my($USAGE) = "Usage: $0: [[--debug]|[-d]]+ [--test] [--description] [--link] [--no-title] [--no-feedname] [[--version] [-V]] [[--columns=int] [-c=int]] [--numfeeds=number] [--onlyfeeds=regexp] [--reversetime] [--username=s] [feedurl]...\n";
my $version = "1.23-baka";
#my $agent = "TheYoke/$version (+http://www.mackers.com/projects/theyoke/) ";
my $agent = "Firefox";
my @OUTPUT;
my @feed_urls;
my (%OPTIONS);
my $exit_val = 0;

Getopt::Long::Configure("bundling", "no_ignore_case", "no_auto_abbrev", "no_getopt_compat", "require_order");
GetOptions(\%OPTIONS, 'debug|d+', 'test', 'description', 'link', 'title', 'no-title', 'no-feedname', 'version|V+', 'columns|c=i', 'numfeeds=i', 'onlyfeeds=s', 'reversetime', 'username=s') || die $USAGE;


my $config_dir = ".theyoke/";
if ($OPTIONS{'username'}) {
  $config_dir = ".theyoke/" . $OPTIONS{'username'} . "/";
}

my $feeds_dir = $config_dir . ".feeds/";
my $feeds_file = $config_dir . "feeds";

if ($OPTIONS{'version'}) {
	print "$0 version $version\n";
	exit(0);
}

### Check for files and dirs. If none, create ###
unless (-d $config_dir || $#ARGV >= 0) {
	mkdir ($config_dir) || die ("Couldn't create directory $config_dir");
}
unless (-d $feeds_dir || $#ARGV >= 0) {
	mkdir ($feeds_dir) || die ("Couldn't create directory $feeds_dir");
}
unless (-f $feeds_file || $#ARGV >= 0) {
	if (open(FEEDS, ">> $feeds_file")) {
		# TODO print feeds file content comments
		print FEEDS "";
		close FEEDS;
	}
	exit(0);
}

### Read feeds file ###
if ($#ARGV >= 0) {
	foreach (@ARGV) {
		my $u1 = URI->new($_);
		push(@feed_urls, $u1);
	}
} else {
	if (open(FEEDS, "< $feeds_file")) {
		while (<FEEDS>) {
			next if (/^#/);
			next unless (/\w/);
			my $u1 = URI->new($_);
			push (@feed_urls, $u1);
		}
	} else {
		print STDERR "theyoke: could not open $feeds_file\n";
		exit(-1);
	}
}

if (scalar(@feed_urls) == 0) {
	print STDERR "theyoke: no feeds found. please enter some URLs in $feeds_file (or as command line argument)\n";
}

### Create new files if necessary
foreach my $feed_url (@feed_urls) {
	$feed_url = $feed_url->as_string;
	my $file_path = $feeds_dir . &get_checksum($feed_url);
	unless (-f $file_path || $#ARGV >= 0) {
		print STDERR "theyoke: adding feed for $feed_url\n";
		if (open (FEED, "> $file_path")) {
			print FEED "$feed_url\n0\nno_digest_yet\nno_title_yet\nno_etag_yet\n";
			close FEED;
		} else {
			print STDERR "theyoke: couldn't write to $feed_url\n";
		}
	}
}

### Create the user agent ###
my $ua = LWP::UserAgent->new(
	env_proxy => 1,
	keep_alive => 0,
	timeout => 30,
	agent => $agent,
	);

### For each feed file ###
my $count = 0;
my $dont_have_content = 1;
print STDERR "theyoke: Syndicating first $OPTIONS{'numfeeds'} feeds.\n" if ($OPTIONS{'debug'} && defined($OPTIONS{'numfeeds'}));
foreach my $feed_url (@feed_urls) {
	last if (defined($OPTIONS{'numfeeds'}) && $count++ == $OPTIONS{'numfeeds'});

	if ($OPTIONS{'onlyfeeds'} && $feed_url !~ /$OPTIONS{'onlyfeeds'}/) {
		print STDERR "theyoke: Skipping... not in /$OPTIONS{'onlyfeeds'}/\n" if ($OPTIONS{'debug'});
		next;
	}

	### get the filename
	my $file_digest = &get_checksum($feed_url);
	my $file_digest_path = $feeds_dir . $file_digest;

	#### open the file
	my $previous_content_digest = "no_digest_yet";
	my $last_title = "no_title_yet";
	my $last_mod = 0;
	my $etag = "no_etag_yet";
	if ($#ARGV < 0) {
		if (open(FEED, "< $file_digest_path")) {
			# 1st line: url
			my $this_url = <FEED>;
			# 2nd line: last modified system time
			$last_mod = <FEED>;
			chomp($last_mod);
			# 3rd line: previous checksum for whole body
			$previous_content_digest = <FEED>;
			chomp($previous_content_digest);
			# 4th line: previous checksum for last known item
			$last_title = <FEED>;
			chomp($last_title);
			# 5th line: etag
			$etag = <FEED>;
			chomp($etag);
			close FEED;
			unless (($previous_content_digest ne "") && ($last_title ne "") && ($etag ne "")) {
				print STDERR "theyoke: $file_digest_path is corrupt or you're using a new version of theyoke. will regenerate next time...\n";
				unlink $file_digest_path;
				next;
			}
		} else {
			die ("theyoke: couldn't open $file_digest_path");
		}
	}

	### send request to see if not modified
	$| = 1;
	print STDERR "theyoke: Getting \"$feed_url\" - " if ($OPTIONS{'debug'});
	my $head = HTTP::Headers->new;
	$head->if_modified_since($last_mod);
	$head->push_header("If-None-Match" => $etag);
	my $req = HTTP::Request->new("GET", $feed_url, $head);
	print STDERR $req->as_string if ($OPTIONS{'debug'} > 1);
	my $resp = $ua->request($req);
	my $content;
	if ($resp->code == 304) {
		print STDERR " got a 304, skipping\n" if ($OPTIONS{'debug'});
		$| = 0;
		next;
	} elsif ($resp->is_success) {
		print STDERR " got " . $resp->code . "\n" if ($OPTIONS{'debug'});
		$content = $resp->content();
		$| = 0;
	} else {
		print STDERR "theyoke: \"$feed_url\": got " . $resp->code . ", skipping\n";
		$| = 0;
		next;
	}

	### skip if checksums match (i.e. head lied - no new content)
	my $new_last_title = "";
	my $new_content_digest = &get_checksum($content);
	if ($new_content_digest eq $previous_content_digest) {
		print STDERR "theyoke: checksums match, skipping\n" if ($OPTIONS{'debug'});
	} else {

		### new content - parse the rss
		my $newtitle = 0;
		my $rss = new XML::RSS;
		my $rss_title = "";
		{
			# XML::RSS seems to always through a DIE
			#local $SIG{__DIE__} = sub { print STDERR "theyoke: RSS parser error on \"$feed_url\".\n"; };
			eval {
				$rss->parse($content);
			};
			if ($@) {
				print STDERR "theyoke: RSS parser error on \"$feed_url\": $@\n";
				next;
			}
		}
		$rss_title = $rss->channel('title');

		### check for no items
		if (@{$rss->{'items'}} == 0) {
			print STDERR "theyoke: no RSS items found in \"$feed_url\". bad RSS?\n";
			next;
		}

		### check for no title
		if ($rss_title eq "") {
			print STDERR "theyoke: no channel title found for \"$feed_url\". bad RSS?\n";
			next;
		}

		### look for new items
		foreach my $item (@{$rss->{'items'}}) {
			my $this_description = $item->{'description'};
			my $this_title = $item->{'title'};
			my $this_link = $item->{'link'};
			my $wassname = "";
			if ($this_title ne "") {
				$wassname = $this_title;
			} elsif ($this_description ne "") {
				#$wassname = substr($this_description,0,30) . "...";
				$wassname = $this_description;
			} elsif ($this_link ne "") {
				$wassname = $this_link;
			} else {
				next;
			}
			my $this_wassname_digest = &get_checksum($wassname);
			if ($this_wassname_digest ne $last_title) {
				# aha! new content
				my ($columns, $rows) = Term::Size::chars *STDOUT{IO};

				$columns = $OPTIONS{'columns'} if (defined($OPTIONS{'columns'}));
				$columns = 32768 if ($columns < 10);

				$wassname = HTML::FormatText->format_string($wassname);
				$wassname =~ s/[\r\n]/ /g;
				$wassname =~ s/\s+$//g;

				my $printy = "";

                                if (!$OPTIONS{'no-feedname'} && $this_title) {
                                    $printy .= "$rss_title: ";
                                }

                                if (!$OPTIONS{'no-title'} && $this_title) {
                                    $printy .= $wassname;
                                    if (length($printy) > $columns-4) {
                                            $printy = substr($printy,0,$columns-4) . "...";
                                    }
                                }

                                if ($printy ne "") {
                                    push(@OUTPUT, $printy . "\n");
                                }
                                
				if ($OPTIONS{'description'} && $this_title) {
					$this_description = HTML::FormatText->format_string($this_description);
					$this_description =~ s/[\r\n]\s*/\n\t/g;
                                        $this_description = "\t$this_description" if (!$OPTIONS{'no-feedname'});
					push(@OUTPUT, "$this_description\n");
				}
                                
				if ($OPTIONS{'link'} && $this_title) {
                                        $this_link = "\t$this_link" if (!$OPTIONS{'no-feedname'});
					push(@OUTPUT, "$this_link\n");
				}
				$dont_have_content = 0;
				# save latest title
				if ($new_last_title eq "") {
					$new_last_title = $this_wassname_digest;
				}
			} else {
				last;
			}
		}

		# check for badness
		if ($new_content_digest eq "") {
			print STDERR "theyoke: empty badness for new_content_digest on $feed_url\n";
			next;
		}
	}

	# check for changed rss file but not changed headings
	if ($new_last_title eq "") {
		if ($OPTIONS{'debug'}) {
			if ($new_content_digest ne $previous_content_digest) {
				print STDERR "theyoke: checksums don't match, but ";
			} else {
				print STDERR "theyoke: ";
			}
			print STDERR "no new headlines from on $feed_url\n";
		}
		$new_last_title = $last_title;
	}

	if ($#OUTPUT >= 0) {
		if ($OPTIONS{'reversetime'}) {
			print reverse @OUTPUT;
		} else {
			print @OUTPUT;
		}
		undef(@OUTPUT);
	}

	### save checksum
	if ($ARGV < 1 && !$OPTIONS{'test'}) {
		if (open(FEED, "> $file_digest_path")) {
			# url
			print FEED $feed_url . "\n";
			# last mod
			if ($resp->last_modified) {
				print FEED $resp->last_modified . "\n";
			} else {
				print FEED $resp->date . "\n";
			}
			# content checksum
			print FEED $new_content_digest . "\n";
			# title checksum
			print FEED $new_last_title . "\n";
			# etag
			if ($resp->header("ETag")) {
				print FEED $resp->header("ETag") . "\n";
			} else {
				print FEED "no_etag\n";
			}
			close FEED;
		} else {
			die ("Couldn't write to $file_digest_path");
		}
	}
}

$exit_val = 2 if $dont_have_content;

exit($exit_val);

sub get_checksum {
	my $tent = md5_base64(encode_utf8($_[0]));
	$tent =~ s/\W/_/g;
	print STDERR $_[0] . " encoding as $tent\n" if ($OPTIONS{'debug'} > 1);
	return $tent;
}


