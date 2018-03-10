package Git::SVN::Authors;

use 5.008;
use strict;
use warnings;

use Carp qw(croak);

use Git qw(
	command_oneline
);

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(check_author);


# '<svn username> = real-name <email address>' mapping based on git-svnimport:
sub load_authors {
	my $cmd = shift;

	open my $authors, '<', $::_authors or die "Can't open $::_authors $!\n";
	my $log = $cmd eq 'log';
	while (<$authors>) {
		chomp;
		next unless /^(.+?|\(no author\))\s*=\s*(.+?)\s*<(.*)>\s*$/;
		my ($user, $name, $email) = ($1, $2, $3);
		if ($log) {
			$Git::SVN::Log::rusers{"$name <$email>"} = $user;
		} else {
			$::users{$user} = [$name, $email];
		}
	}
	close $authors or croak $!;
}

sub setup_authors_prog {
	if (defined $::_authors_prog) {
		my $abs_file = File::Spec->rel2abs($::_authors_prog);
		$::_authors_prog = "'" . $abs_file . "'" if -x $abs_file;
	}
}

sub call_authors_prog {
	my ($orig_author) = @_;
	$orig_author = command_oneline('rev-parse', '--sq-quote', $orig_author);
	my $author = `$::_authors_prog $orig_author`;
	if ($? != 0) {
		die "$::_authors_prog failed with exit code $?\n"
	}
	if ($author =~ /^\s*(.+?)\s*<(.*)>\s*$/) {
		my ($name, $email) = ($1, $2);
		return [$name, $email];
	} else {
		die "Author: $orig_author: $::_authors_prog returned "
			. "invalid author format: $author\n";
	}
}

sub check_author {
	my ($author) = @_;
	if (!defined $author || length $author == 0) {
		$author = '(no author)';
	}
	if (!defined $::users{$author}) {
		if (defined $::_authors_prog) {
			$::users{$author} = call_authors_prog($author);
		} elsif (defined $::_authors) {
			die "Author: $author not defined in $::_authors file\n";
		}
	}
	$author;
}

1;
