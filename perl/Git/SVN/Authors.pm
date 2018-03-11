package Git::SVN::Authors;

use 5.008;
use strict;
use warnings;

use Carp qw(croak);

use Git qw(
	command_oneline
);

=head1 NAME

GIT::SVN::Authors - mapping of author- and committer names in git-svn

=head1 SYNOPSIS

	use Git::SVN:Authors;
	my $svn_authors = Git::SVN::Authors->new(
		authors_file => ".svn-authors",
		authors_prog => "",
		use_log_author => 1
	);

	my $log_entry = {
		author => "johndoe",
		log => "commit some minor fixes

From: Dr. Evil <evil@genius.example.com>
	};
	$svn_authors->update_author_committer(\%log_entry, $uuid);

	my $svn_user = $svn_authors->reverse_map("John Doe <john.doe@example.com");


=head1 DESCRIPTION

This module encapsulates the mapping of author identifiers between Git
and Subversion. Subversion commits only record a simple name (e.g.
C<johndoe>) but Git uses Name/Email pairs and distinguishes between
the "committer" and the "author" of a commit.

Do not use it unless you are developing git-svn.  The interface will
change as git-svn evolves.

=cut

sub new {
	my ($class, %params) = @_;

	my $self = bless {
		authors_file => $params{authors_file},
		authors_prog => $params{authors_prog},
		use_log_author => $params{use_log_author},
		users => { },
		rusers => { }
	}, $class;

	$self->_load_authors_file;
	$self->_setup_authors_prog;

	return $self;
}

# '<svn username> = real-name <email address>' mapping based on git-svnimport:
sub _load_authors_file {
	my ($self) = @_;
	my $authors_file = $self->{authors_file};
	return unless $authors_file;
	open my $authors, '<', $authors_file or die "Can't open $authors_file $!\n";
	while (<$authors>) {
		chomp;
		next unless /^(.+?|\(no author\))\s*=\s*(.+?)\s*<(.*)>\s*$/;
		my ($user, $name, $email) = ($1, $2, $3);
		$self->{users}->{$user} = [$name, $email];
		$self->{rusers}->{"$name <$email>"} = $user;
	}
	close $authors or croak $!;
}

sub _setup_authors_prog {
	my ($self) = @_;
	my $authors_prog = $self->{authors_prog};
	if (defined $authors_prog) {
		my $abs_file = File::Spec->rel2abs($authors_prog);
		$self->{authors_prog} = "'" . $abs_file . "'" if -x $abs_file;
	}
}

sub _call_authors_prog {
	my ($self, $orig_author) = @_;
	my $authors_prog = $self->{authors_prog};
	$orig_author = command_oneline('rev-parse', '--sq-quote', $orig_author);
	my $author = `$authors_prog $orig_author`;
	if ($? != 0) {
		die "$authors_prog failed with exit code $?\n"
	}
	if ($author =~ /^\s*(.+?)\s*<(.*)>\s*$/) {
		my ($name, $email) = ($1, $2);
		return [$name, $email];
	} else {
		die "Author: $orig_author: $authors_prog returned "
			. "invalid author format: $author\n";
	}
}

sub _check_author {
	my ($self, $author) = @_;
	if (!defined $author || length $author == 0) {
		$author = '(no author)';
	}
	if (!defined $self->{users}->{$author}) {
		if (defined $self->{authors_prog}) {
			$self->{users}->{$author} = $self->_call_authors_prog($author);
		} elsif (defined $self->{authors_file}) {
			die "Author: $author not defined in $$self->{authors_file} file\n";
		}
	}
	$author;
}

sub update_author_committer {
	my ($self, $log_entry, $uuid) = @_;

	my $author = $$log_entry{author} = $self->_check_author($$log_entry{author});
	my ($name, $email) = defined $self->{users}->{$author} ? @{$self->{users}->{$author}}
						       : ($author, undef);

	my ($commit_name, $commit_email) = ($name, $email);
	if ($self->{use_log_author}) {
		my $name_field;
		if ($$log_entry{log} =~ /From:\s+(.*\S)\s*\n/i) {
			$name_field = $1;
		} elsif ($$log_entry{log} =~ /Signed-off-by:\s+(.*\S)\s*\n/i) {
			$name_field = $1;
		}
		if (!defined $name_field) {
			if (!defined $email) {
				$email = $name;
			}
		} elsif ($name_field =~ /(.*?)\s+<(.*)>/) {
			($name, $email) = ($1, $2);
		} elsif ($name_field =~ /(.*)@/) {
			($name, $email) = ($1, $name_field);
		} else {
			($name, $email) = ($name_field, $name_field);
		}
	}

	$email = "$author\@$uuid" unless defined $email;
	$commit_email = "$author\@$uuid" unless defined $commit_email;

	$$log_entry{name} = $name;
	$$log_entry{email} = $email;
	$$log_entry{commit_name} = $commit_name;
	$$log_entry{commit_email} = $commit_email;
}

sub reverse_map {
	my ($self, $author) = @_;
	my $au;
	if ($self->{authors_file}) {
		$au = $self->{rusers}->{$author} || undef;
	}
	if (!$au) {
		($au) = ($author =~ /<([^>]+)\@[^>]+>$/);
	}
	$au;
}

1;
