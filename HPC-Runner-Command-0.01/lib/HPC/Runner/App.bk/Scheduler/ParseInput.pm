package HPC::Runner::App::Scheduler::ParseInput;

use Moose::Role;

=head1 HPC::Runner::App::Scheduler::ParseInput

Parse the infile for HPC params, jobs, and batches

=head2 Subroutines

=head3 parse_file_slurm

Parse the file looking for the following conditions

lines ending in `\`
wait
nextnode

Batch commands in groups of $self->cpus_per_task, or smaller as wait and nextnode indicate

=cut

sub parse_file_slurm {
    my $self = shift;

    my $fh = IO::File->new( $self->infile, q{<} )
        or print "Error opening file  "
        . $self->infile . "  "
        . $!;    # even better!

    $self->reset_cmd_counter;
    $self->reset_batch_counter;

    #If we pass in commandline afterok
    #This is not supported within a file
    #HPC afterok=thing1,thing2 -> Not supported

    if ( $self->has_afterok ) {
        $self->jobs->{$self->jobname}->{submitted} = 1;
        $self->jobs->{$self->jobname}->{scheduler_ids} = $self->afterok;

        my $oldjob = $self->jobname;
        $self->increase_jobname();
        $self->deps($oldjob);
    }

    while (<$fh>) {
        my $line = $_;
        next unless $line;
        next unless $line =~ m/\S/;
        $self->process_lines($line);
    }

    close($fh);

}

sub process_lines {
    my $self = shift;
    my $line = shift;

    $self->check_sanity($line);
    $self->check_hpc_meta($line);
    $self->check_note_meta($line);

    return if $line =~ m/^#/;

    $self->check_add_to_jobs();
    $self->check_lines_add_cmd($line);
}


=head3 check_lines_add_cmd

Append to the command

We check for a few cases

1. A line that is terminated by the usual newline character

    echo "hello!"

2. A multiline command in the usual bash sense

    echo "goodbye!" && \
        echo "not again!"

3. The command is wait. Submit jobs we already have to the scheduler, and any jobs after 'wait', depend upon jobs before 'wait' finishing.

    wait

4. Deprecated! The command is 'newnode' on a line by itself. Submit all the previous jobs, but no dependenciies. Instead please use '#HPC commands_per_node' within your job file.

    #HPC jobname=job01
    #HPC commands_per_node=1
    #HPC cpus_per_task=12

    gzip VERY_LARGE_FILE
    gzip OTHER_VERY_LARGE_FILE

=cut

sub check_lines_add_cmd {
    my $self = shift;
    my $line = shift;

    return unless $line;

    $self->add_cmd($line);

    if ( $line =~ m/\\$/ ) {
        return;
    }
    elsif ( $self->match_cmd(qr/^wait$/) ) {

        #submit this batch and get the job id so the next can depend upon it
        $self->clear_cmd;

        #If we're using 'wait' its linear deps
        $self->check_add_to_jobs;
        my $oldjob = $self->jobname;
        $self->increase_jobname();
        $self->deps($oldjob);
    }

    push( @{ $self->jobs->{ $self->jobname }->{cmds} }, $self->cmd )
        if $self->has_cmd;

    $self->inc_cmd_counter;
    $self->clear_cmd;
}

=head3 check_sanity

Do some sanity checks. So far we only check for nohup, because nohup confuses schedulers.

#TODO Add check for when line ends with &. This also confuses schedulers

=cut

sub check_sanity {

    #TODO Integrate this with DBM::Deep jobs -> everything will be in there
    my $self = shift;
    my $line = shift;

    #Do a sanity check for nohup
    if ( $line =~ m/^nohup/ ) {
        die print
            "You cannot submit jobs to the queue using nohup! Please remove nohup and try again.\n";
    }
}

=head3 check_note_meta

Check for lines starting with #NOTE - used to pass per process job_tags

=cut

sub check_note_meta {
    my $self = shift;
    my $line = shift;

    return unless $line =~ m/^#NOTE/;
    $self->add_cmd($line);
}

=head3 check_hpc_meta

allow for changing parameters mid through the script

#Job1
echo "this is job one" && \
    bin/dostuff bblahblahblah

#HPC cpu_per_task=12

echo "This is my new job with new HPC params!"

=cut

sub check_hpc_meta {
    my $self = shift;
    my $line = shift;
    my ( @match, $t1, $t2 );

    return unless $line =~ m/^#HPC/;
    chomp($line);

    @match = $line =~ m/HPC (\w+)=(.+)$/;
    ( $t1, $t2 ) = ( $match[0], $match[1] );

    if ( !$self->can($t1) ) {
        print "Option $t1 is an invalid option!\n";
        return;
    }

    #Only process jobnames
    if ( $t1 eq 'jobname' || $t1 eq 'deps' ) {
        $self->$t1($t2);
        return;
    }

    push( @{ $self->jobs->{ $self->jobname }->{hpc_meta} }, $line );
}

1;
