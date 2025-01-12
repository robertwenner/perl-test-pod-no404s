package Test::Pod::No404s;

# ABSTRACT: Using this test module will check your POD for any http 404 links

# Import the modules we need
use Pod::Simple::Text;
use LWP::UserAgent;
use URI::Find;
use Test::Pod ();

# setup our tests and etc
use Test::Builder;
my $Test = Test::Builder->new;
my %ignore_urls;

# auto-export our 2 subs
use parent qw( Exporter );
our @EXPORT = qw( pod_file_ok all_pod_files_ok ); ## no critic ( ProhibitAutomaticExportation )

=method pod_file_ok

C<pod_file_ok()> will okay the test if there is no http(s) links present in the POD or if all links are not an error. Furthermore, if the POD was
malformed as reported by L<Pod::Simple>, the test will fail and not attempt to check the links.

When it fails, C<pod_file_ok()> will show any failing links as diagnostics.

The optional second argument TESTNAME is the name of the test.  If it is omitted, C<pod_file_ok()> chooses a default
test name "404 test for FILENAME".

=cut

sub pod_file_ok {
	my $file = shift;
	my $name = @_ ? shift : "404 test for $file";

	if ( ! -f $file ) {
		$Test->ok( 0, $name );
		$Test->diag( "$file does not exist" );
		return;
	}

	# Parse the POD!
	my $parser = Pod::Simple::Text->new;
	my $output;
	$parser->output_string( \$output );
	$parser->complain_stderr( 0 );
	$parser->no_errata_section( 0 );
	$parser->no_whining( 0 );

	# safeguard ourself against crazy parsing failures
	eval { $parser->parse_file( $file ) };
	if ( $@ ) {
		$Test->ok( 0, $name );
		$Test->diag( "Unable to parse POD in $file => $@" );
		return;
	}

	# is POD well-formed?
	if ( $parser->any_errata_seen ) {
		$Test->ok( 0, $name );
		$Test->diag( "Unable to parse POD in $file" );

		# TODO ugly, but there is no other way to get at it?
		foreach my $l ( keys %{ $parser->{errata} } ) {
			$Test->diag( " * errors seen in line $l:" );
			$Test->diag( "   * $_" ) for @{ $parser->{errata}{$l} };
		}

		return 0;
	}

	_load_ignore_urls();

	# Did we see POD in the file?
	if ( $parser->doc_has_started ) {
		my @links;
		my $finder = URI::Find->new( sub {
			my($uri, $orig_uri) = @_;
			my $scheme = $uri->scheme;
			if ( defined $scheme and ( $scheme eq 'http' or $scheme eq 'https' ) ) {
				# we skip RFC 6761 addresses reserved for testing and etc
				if ( $uri->host !~ /(?:test|localhost|invalid|example|example\.com|example\.net|example\.org)$/ ) {
					push @links, [$uri,$orig_uri];
				}
			}
		} );
		$finder->find( \$output );

		if ( scalar @links ) {
			# Verify the links!
			my $ok = 1;
			my @errors;
			my $ua = LWP::UserAgent->new;
			foreach my $l ( @links ) {
				if ( $ignore_urls{$l->[0]} ) {
					$Test->diag( "Ignoring $l->[0]" );
					next;
				}

				$Test->diag( "Checking $l->[0]" );
				my $response = $ua->head( $l->[0] );
				if ( $response->is_error ) {
					$ok = 0;
					push( @errors, [ $l->[1], $response->status_line ] );
				}
			}

			$Test->ok( $ok, $name );
			foreach my $e ( @errors ) {
				$Test->diag( "Error retrieving '$e->[0]': $e->[1]" );
			}
		} else {
			$Test->ok( 1, $name );
		}
	} else {
		$Test->ok( 1, $name );
	}

	return 1;
}

sub _load_ignore_urls {
	return if ( %ignore_urls );

	# Put a dummy item in %ignore_urls to not try to keep loading it over and over.
	my $dummy = q{#};
	$ignore_urls{ $dummy } = 1;

	my $config = '.no404s-ignore';
	$Test->diag( "Trying to load ignore URLs from $config" );
	if ( -f $config ) {
		open(my $F, '<', $config) or do {
			$Test->diag( "Error reading $config: $!" );
			return;
		};
		foreach my $line ( <$F> ) {
			$line =~ s/^\s+//xms;
			$line =~ s/\s+$//xms;
			$ignore_urls{ $line } = 1;
		}
		close $F;
	}
	return;
}

=method all_pod_files_ok

This function is what you will usually run. It automatically finds any POD in your distribution and runs checks on them.

Accepts an optional argument: an array of files to check. By default it checks all POD files it can find in the distribution. Every file it finds
is passed to the C<pod_file_ok> function.

=cut

sub all_pod_files_ok {
	my @files = @_ ? @_ : Test::Pod::all_pod_files();

	$Test->plan( tests => scalar @files );

	my $ok = 1;
	foreach my $file ( @files ) {
		pod_file_ok( $file ) or undef $ok;
	}

	return $ok;
}

1;

=pod

=head1 SYNOPSIS

	#!/usr/bin/perl
	use strict; use warnings;

	use Test::More;

	eval "use Test::Pod::No404s";
	if ( $@ ) {
		plan skip_all => 'Test::Pod::No404s required for testing POD';
	} else {
		all_pod_files_ok();
	}

=head1 DESCRIPTION

This module looks for any http(s) links in your POD and verifies that they will not return a 404. It uses L<LWP::UserAgent> for the heavy
lifting, and simply lets you know if it failed to retrieve the document. More specifically, it uses $response->is_error as the "test."

This module does B<NOT> check "pod" or "man" links like C<LE<lt>Test::PodE<gt>> in your pod. For that, please check out L<Test::Pod::LinkCheck>.

Normally, you wouldn't want this test to be run during end-user installation because they might have no internet! It is HIGHLY recommended
that this be used only for module authors' RELEASE_TESTING phase. To do that, just modify the synopsis to add an env check :)

=head1 EXPORT

Automatically exports the two subs.

=head1 SEE ALSO
Test::Pod::LinkCheck

=cut
