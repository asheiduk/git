package Git::SVN::Authors;

use 5.008;
use strict;
use warnings;

use Carp qw(croak);


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

1;
