package TestsFor::HPC::Runner::Command::Test002;

use Test::Class::Moose;
use HPC::Runner::Command;
use Cwd;
use FindBin qw($Bin);
use File::Path qw(make_path remove_tree);
use IPC::Cmd qw[can_run];
use Data::Dumper;
use Capture::Tiny ':all';
use Slurp;
use File::Slurp;

sub make_test_dir {

    my $test_dir;

    my @chars = ( 'a' .. 'z', 'A' .. 'Z', 0 .. 9 );
    my $string = join '', map { @chars[ rand @chars ] } 1 .. 8;

    if ( exists $ENV{'TMP'} ) {
        $test_dir = $ENV{TMP} . "/hpcrunner/$string";
    }
    else {
        $test_dir = "/tmp/hpcrunner/$string";
    }

    make_path($test_dir);
    make_path("$test_dir/script");

    chdir($test_dir);

    if ( can_run('git') && !-d $test_dir . "/.git" ) {
        system('git init');
    }

    open( my $fh, ">$test_dir/script/test002.1.sh" );
    print $fh <<EOF;
#HPC jobname=job01
#HPC cpus_per_task=12
#HPC commands_per_node=1

#NOTE job_tags=Sample1
echo "hello world from job 1" && sleep 5

#NOTE job_tags=Sample2
echo "hello again from job 2" && sleep 5

#HPC jobname=job02
#HPC deps=job01
#NOTE job_tags=Sample3
echo "goodbye from job 3"
echo "hello again from job 3" && sleep 5
EOF

    close($fh);

    return $test_dir;
}

sub test_shutdown {

    chdir("$Bin");
    if ( exists $ENV{'TMP'} ) {
        remove_tree( $ENV{TMP} . "/hpcrunner" );
    }
    else {
        remove_tree("/tmp/hpcrunner");
    }
}

sub test_000 : Tags(require) {
    my $self = shift;

    require_ok('HPC::Runner::Command');
    require_ok('HPC::Runner::Command::Utils::Base');
    require_ok('HPC::Runner::Command::Utils::Log');
    require_ok('HPC::Runner::Command::Utils::Git');
    require_ok('HPC::Runner::Command::submit_jobs::Utils::Scheduler');
    ok(1);
}

sub construct {

    my $test_dir = make_test_dir;

    my $t = "$test_dir/script/test002.1.sh";
    MooseX::App::ParsedArgv->new(
        argv => [
            "submit_jobs",    "--infile",
            $t,               "--outdir",
            "$test_dir/logs", "--hpc_plugins",
            "Dummy",
        ]
    );

    my $test = HPC::Runner::Command->new_with_command();
    $test->logname('slurm_logs');
    $test->log( $test->init_log );
    return $test;
}

sub test_003 : Tags(construction) {

    my $test     = construct();
    my $test_dir = getcwd();

    is( $test->outdir, "$test_dir/logs", "Outdir is logs" );
    is( $test->infile, "$test_dir/script/test002.1.sh", "Infile is ok" );

    isa_ok( $test, 'HPC::Runner::Command' );
}

sub test_005 : Tags(submit_jobs) {

    my $test_dir = make_test_dir;
    my $test     = construct();
    my $cwd      = getcwd();

    $test->first_pass(1);
    $test->parse_file_slurm();
    $test->schedule_jobs();
    $test->iterate_schedule();

    $test->reset_batch_counter;
    $test->first_pass(0);
    $test->iterate_schedule();

    my $logdir = $test->logdir;
    my $outdir = $test->outdir;

    my $got = read_file( $test->outdir . "/001_job01.sh" );
    chomp($got);

    $got =~ s/--metastr.*//g;
    $got =~ s/--version.*//g;

    my $expect = <<EOF;
#!/bin/bash
#
#SBATCH --share
#SBATCH --get-user-env
#SBATCH --job-name=001_job01
#SBATCH --output=$logdir/001_job01.log
#SBATCH --cpus-per-task=12

cd $cwd
hpcrunner.pl execute_job \\
EOF
    $expect .= "\t--procs 4 \\\n";
    $expect .= "\t--infile $outdir/001_job01.in \\\n";
    $expect .= "\t--outdir $outdir \\\n";
    $expect .= "\t--logname 001_job01 \\\n";
    $expect .= "\t--process_table $logdir/001-process_table.md \\\n";

    #TODO FIX THIS TEST
    #ok( $got =~ m/expected/, 'this is like that' );

    ok(1);
}

sub test_007 : Tags(check_hpc_meta) {

    my $test = construct();

    my $line = "#HPC module=thing1,thing2\n";
    $test->process_hpc_meta($line);

    is_deeply( [ 'thing1', 'thing2' ], $test->module, 'Modules pass' );
}

sub test_008 : Tags(check_hpc_meta) {
    my $self = shift;

    my $test = construct();

    my $line = "#HPC jobname=job03\n";
    $test->process_hpc_meta($line);

    $line = "#HPC deps=job01,job02\n";
    $test->process_hpc_meta($line);

    is_deeply( [ 'job01', 'job02' ], $test->deps, 'Deps pass' );
    is_deeply( { job03 => [ 'job01', 'job02' ] },
        $test->job_deps, 'Job Deps Pass' );
}

sub test_009 : Tags(check_hpc_meta) {
    my $self = shift;

    my $test = construct();

    my $line = "#HPC jobname=job01\n";
    $test->process_hpc_meta($line);

    is_deeply( 'job01', $test->jobname, 'Jobname pass' );
}

sub test_010 : Tags(check_note_meta) {
    my $self = shift;

    my $test = construct();

    my $line = "#NOTE job_tags=SAMPLE_01\n";
    $test->check_note_meta($line);

    is_deeply( $line, $test->cmd, 'Note meta passes' );
}

sub test_011 : Tags(check_hpc_meta) {
    my $self = shift;

    my $test = construct();

    my $line = "#HPC jobname=job01\n";
    $test->process_hpc_meta($line);
    $test->check_add_to_jobs();

    ok(1);
}

sub test_012 : Tags(job_stats) {
    my $self = shift;

    my $test = construct();

    $test->first_pass(1);
    $test->parse_file_slurm();
    $test->schedule_jobs();
    $test->iterate_schedule();

    my $job_stats = {
        'tally_commands' => 1,
        'batches'        => {
            '001_job01' => {
                'jobname'  => 'job01',
                'batch'    => '001',
                'commands' => 1,
            },
            '002_job01' => {
                'jobname'  => 'job01',
                'batch'    => '002',
                'commands' => 1,
            },
            '004_job02' => {
                'batch'    => '004',
                'jobname'  => 'job02',
                'commands' => 1,
            },
            '003_job02' => {
                'commands' => 1,
                'batch'    => '003',
                'jobname'  => 'job02',
            }
        },
        'total_batches' => 4,
        'jobnames'      => {
            'job01' => [ '001_job01', '002_job01' ],
            'job02' => [ '003_job02', '004_job02' ]
        },
        'total_processes' => 4,
    };

    is_deeply( $job_stats, $test->job_stats, 'Job stats pass' );
    is_deeply( [ 'job01', 'job02' ], $test->schedule, 'Schedule passes' );

    ok(1);
}

sub test_013 : Tags(jobname) {
    my $self = shift;

    my $test = construct();

    is( 'hpcjob_001', $test->jobname, 'Jobname is ok' );
}

sub test_014 : Tags(job_stats) {
    my $self = shift;

    my $test = construct();

    $test->first_pass(1);
    $test->parse_file_slurm();
    $test->schedule_jobs();
    $test->iterate_schedule();

    my $expect = {
        'job01' => {
            'hpc_meta' =>
                [ '#HPC cpus_per_task=12', '#HPC commands_per_node=1' ],
            'scheduler_ids' => [],
            'submitted'     => '0',
            'deps'          => [],
            'cmds'          => [
                '#NOTE job_tags=Sample1
echo "hello world from job 1" && sleep 5
',
                '#NOTE job_tags=Sample2
echo "hello again from job 2" && sleep 5
'
            ],
        },
        'job02' => {
            'scheduler_ids' => [],
            'hpc_meta'      => [],
            'submitted'     => '0',
            'deps'          => ['job01'],
            'cmds'          => [
                '#NOTE job_tags=Sample3
echo "goodbye from job 3"
',
                'echo "hello again from job 3" && sleep 5
'
            ],
        },
    };

    is_deeply( $expect, $test->jobs, 'Test jobs passes' );

    $test->reset_batch_counter;
    $test->first_pass(0);
    $test->schedule_jobs();
    $test->iterate_schedule();

    is( $test->jobs->{'job01'}->count_scheduler_ids, 2 );
    is( $test->jobs->{'job02'}->count_scheduler_ids, 2 );
    is( $test->jobs->{'job01'}->submitted,           1 );
    is( $test->jobs->{'job02'}->submitted,           1 );
    ok(1);
}

sub print_diff {
    my $got    = shift;
    my $expect = shift;

    use Text::Diff;

    my $diff = diff \$got, \$expect;
    diag("Diff is\n\n$diff\n\n");

    my $fh;
    open( $fh, ">got.diff" ) or die print "Couldn't open $!\n";
    print $fh $got;
    close($fh);

    open( $fh, ">expect.diff" ) or die print "Couldn't open $!\n";
    print $fh $expect;
    close($fh);

    open( $fh, ">diff.diff" ) or die print "Couldn't open $!\n";
    print $fh $diff;
    close($fh);

    ok(1);
}

1;
