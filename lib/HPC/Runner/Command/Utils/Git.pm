package HPC::Runner::Command::Utils::Git;

use MooseX::App::Role;

use namespace::autoclean;
use Git::Wrapper;
use Git::Wrapper::Plus::Ref::Tag;
use Git::Wrapper::Plus::Tags;
use Git::Wrapper::Plus::Branches;
use Perl::Version;
use Sort::Versions;
use Try::Tiny;

use Cwd;
use File::Path qw(make_path);
use File::Slurp;
use File::Spec;
use Archive::Tar;
use Data::Dumper;

#TODO add git flow support

option 'version' => (
    is => 'rw',
    required => 0,
    predicate => 'has_version',
    documentation => 'run version',
);

has 'git_dir' => (
    is => 'rw',
    isa => 'Str',
    default => sub {return cwd()},
    predicate => 'has_git_dir',
);

has 'git' => (
    is => 'rw',
    predicate => 'has_git',
    required => 0,
);

has 'current_branch' => (
    is => 'rw',
    isa => 'Str',
    required => 0,
    predicate => 'has_current_branch',
);

#has 'remote' => (
    #is => 'rw',
    #isa => 'Str',
    #required => 0,
    #predicate => 'has_remote',
#);

#TODO Create option for adding archive

sub init_git{
    my $self = shift;

    my $git = Git::Wrapper->new(cwd()) or die print "Could not initialize Git::Wrapper $!\n";

    try {
        my @output = $git->rev_parse(qw(--show-toplevel));
        $self->git_dir($output[0]);
        $git = Git::Wrapper->new($self->git_dir);
        $self->git($git);
    }

}

sub dirty_run{
    my($self) = shift;

    return unless $self->has_git;

    my $dirty_flag = $self->git->status->is_dirty;

    if($dirty_flag){
        print "There are uncommited files in your repo!\nPlease commit these files before running.";
    }
}

sub git_info{
    my $self = shift;

    return unless $self->has_git;

    $self->branch_things;
    $self->get_version;
}

sub branch_things{
    my($self) = @_;

    return unless $self->has_git;

    my $branches = Git::Wrapper::Plus::Branches->new(
        git => $self->git
    );

    my $current;
    for my $branch ( $branches->current_branch ) {
        $self->current_branch($branch->name);
    }
}

sub git_config{
    my($self) = @_;

    return unless $self->has_git;
    #First time we run this we want the name, username, and email
    my @output = $self->git->config(qw(--list));

    my %config = ();
    foreach my $c (@output){
        my @words = split /=/, $c;
        $config{$words[0]} = $words[1];
    }
    return \%config;
}

sub git_logs{
    my($self) = shift;

    return unless $self->has_git;
    my @logs = $self->git->log;
    return \@logs;
}

sub get_version{
    my($self) = shift;

    return unless $self->has_git;
    return if $self->version;

    my $tags_finder = Git::Wrapper::Plus::Tags->new(
        git => $self->git
    );

    my @versions = ();
    for my $tag ( $tags_finder->tags ) {
        my $name = $tag->name;
        if($name =~ m/(\d+)\.(\d+)/){
            push(@versions, $name);
        }
    }

    if(@versions){
        my  @l = sort {versioncmp($a, $b)} @versions;
        my $v = pop(@l);
        my $pv = Perl::Version->new($v);
        $pv->inc_subversion;
        $pv = "$pv";
        $self->version($pv);
    }
    else{
        $self->version("0.1");
    }

    $self->git_push_tags;
}

sub git_push_tags{
    my($self) = shift;

    return unless $self->has_git;
    my @remote = $self->git->remote;

    $self->git->tag($self->version);

    foreach my $remote (@remote){
        $self->git->push({tags => 1}, $remote);
    }
}

sub create_release{
    my($self) = @_;

    return unless $self->has_git;
    my @filelist = $self->git->ls_files();

    return unless @filelist;
    #make git_dir/archive if it doesn't exist
    make_path($self->git_dir.'/hpc-runner/archive');
    Archive::Tar->create_archive( $self->git_dir."/hpc-runner/archive/archive"."-".$self->version.".tgz", COMPRESS_GZIP, @filelist);
}

1;
