#!/usr/bin/perl -w

# lsfcdsearch.pl - a program to submit cdsearch job to LSF queue.

# Usage: lsfcdsearch.pl <number of processes>

#  This program takes each file in the current directory and submits a
#  blast job to LSF queue. It submits only the specified number of jobs
#  to the queue and waits, till it finds free slot to sumbit more. The
#  program creates an output directory containing the result files and
#  a log directory containing the LSF output logs.

use Cwd;
use Getopt::Std;
use strict;

our (%opt);

getopt( 'iobdesp', \%opt );

#print $opt{i}, ',', $opt{o}, "\n";

my $composite_input  = $opt{i} || undef;
my $composite_output = $opt{o} || undef;

#my $program = $opt{p} || 'blastp';
my $database     = $opt{d} || die "Database is required option\n";
my $blastoptions = $opt{b} || "";
my $engine       = $opt{e} || "SGE";
my $split        = $opt{s} || 1;
my $project_code = $opt{p} || "";

#if ( $opt{e} eq "LSF" || $opt{e} eq "lsf" ) {
#	$engine = "LSF";
#}

#print $composite_input, ',', $composite_output, "\n";

# Blast options

#my $BLAST   = "rpsblast -d cdd -e 0.001 -F T";
my $BLAST = "rpsblast -e 0.001 -F T -d $database";

#my $DB      = "-d $database";
my $OPTIONS = "$blastoptions";

# LSF commands
my $LSF;
my $LSF_OPTIONS = "";

if ( $engine eq "SGE" ) {
    $LSF         = "qsub";
    $LSF_OPTIONS = "-b y -j y -V ";

    if ($project_code) {
        $LSF_OPTIONS .= " -P $project_code";
    }
}
elsif ( $engine eq "LSF" ) {
	$LSF         = 'bsub';
	$LSF_OPTIONS = '-q "unified" -R "linux" -P 0380';
}
else {

}

my @excluded_machines;

#my $LSF_OPTIONS = '-q "unified" -R "linux" -m "lfarm118 lfarm025 lfarm059 others+2"';

# Number of jobs that the script will submit at a time

my $NP = 150;

#if ($ARGV[0]) {
##    $NP = $ARGV[0];
#}

# Output directories
#my $CURRENT_DIR = cwd();

my $CURRENT_DIR = $ENV{PWD};
my $OUTPUT_DIR  = $CURRENT_DIR . '/output';
my $LOG_DIR     = $CURRENT_DIR . '/log';
my $TEMP_DIR    = $CURRENT_DIR . '/tmp';

if ( !stat($OUTPUT_DIR) ) {
    system("mkdir $OUTPUT_DIR") == 0 or die "Can't create output dir!\n";

}

if ( !stat($LOG_DIR) ) {
    system("mkdir $LOG_DIR") == 0 or die "Can't create log dir!\n";
}

if ( !stat($TEMP_DIR) ) {
    system("mkdir $TEMP_DIR") == 0 or die "Can't create log dir!\n";
}

my $total_seq          = 0;
my $total_job          = 0;
my $total_result       = 0;
my $total_returned_job = 0;

if ($composite_input) {
    print STDERR "Splitting input file...";

    #open( INFILE, $opt{i} ) || die "Can't open $opt{i}\n";
    my $fh = open_file( $opt{i} );

    my $lastseq = "";
    my $lastgi  = "";

    #	my $outfilename;
    #	my $data;

    while ( my $line = <$fh> ) {
        if ( $line =~ /^>/ ) {
            $total_seq++;

            #			print STDERR $total_seq%$opt{s},"\n";
            if ( $total_seq != 1 && !( ( $total_seq - 1 ) % $split ) ) {

                #				print STDERR $line, "\n";
                my $outfilename = $TEMP_DIR . '/' . $lastgi . '.lsf';
                open( OUTFILE, ">$outfilename" )
                    || die "Can't open $outfilename\n";
                print OUTFILE $lastseq;
                close(OUTFILE);
                $lastseq = "";
                $lastgi  = "";
            }

            if ($lastgi) {

               #				$outfilename = $TEMP_DIR . '/' . $lastgi . '.lsf';
               #				open( OUTFILE, ">$outfile" ) || die "Can't open $outfile\n";
               #				print OUTFILE $lastseq;
               #				close(OUTFILE);

                $lastseq .= $line;
                $line =~ /^>(\S+)/;
                $lastgi = $1;
                $lastgi =~ s/[^0-9A-Za-z]/\_/g;

            }
            else {
                $lastseq = $line;
                $line =~ /^>(\S+)/;
                $lastgi = $1;
                $lastgi =~ s/[^0-9A-Za-z]/\_/g;

            }
        }
        else {
            $lastseq .= $line;
        }
    }

    if ($lastgi) {
        my $outfile = $TEMP_DIR . '/' . $lastgi . '.lsf';
        open( OUTFILE, ">$outfile" ) || die "Can't open $outfile\n";
        print OUTFILE $lastseq;
        close(OUTFILE);

        #	$lastseq = $line;
        #		$line =~ /^>(\S+)/;
        #		$lastgi = $1;
        #		$lastgi =~ s/[^0-9A-Za-z]/\_/g;
    }
    close($fh);
    print "done.\n";
}

# open the current dir and read one file at a time
opendir( DIR, $TEMP_DIR ) or die "Can't open $TEMP_DIR\n";

my $filename;    # stores the filename in the loop
my @jobs;        # a global array contains running job pids;
my $ext = "";
my %time;
my %pid_2_filename;

# main loop
if ($composite_input) {
    $ext = '.lsf';
}
else {
    $ext = '.fas';
}

while ( defined( $filename = readdir(DIR) ) ) {
    next if ( -d $filename );    # skip if it is a directory

    #   if ($composite_input) {
    #    }
    next
        if ( $filename !~ /$ext$/ );  # skip if the file extension is not ".fas"

    if ( @jobs > $NP ) {              # Process limit has reached

        gotosleep($NP);
    }

    launch_job($filename);
}

close(DIR);
print STDERR "Sucessfully completed scheduling.\n";

gotosleep(0);

#sub get_next_file {

#my $f = undef;
#while ( my $temp = readdir(DIR) ) {
#     next if (-d $temp); # skip if it is a directory

#     $f = $temp;
#     last;
# }

#        close (DIR);
#return $f;
#}

if ($composite_input) {
    print STDERR "Removing temp files ...\n";

    #system ("rmfile.pl \"*.lsf\"");
    #system("rm *.lsf");
    #	system("rm -rf $TEMP_DIR");
    print STDERR "Total sequence: $total_seq\n";
}

my %queries;
my $header_read       = 0;
my $header_line_count = 0;
my $missing_count     = 0;
if ($composite_output) {
	print STDERR "Collating output ...";
	opendir( DIR, $OUTPUT_DIR ) or die "Can't open $OUTPUT_DIR\n";
	#open( OUTFILE, "| bzip2 -c -9 >$opt{o}" ) || die "Can't open $opt{o}\n";
	open( OUTFILE, "| gzip -c -9 >$opt{o}" ) || die "Can't open $opt{o}\n";
	while ( defined( $filename = readdir(DIR) ) ) {

		my $infile = $OUTPUT_DIR . '/' . $filename;
		next if ( -d $infile );

		#		print STDERR $infile, "\n";
		$total_returned_job++;
		open( INFILE, "gunzip  -c $infile|" ) || die "Can't open $infile\n";
		while ( my $line = <INFILE> ) {
			if ( $line =~ /^Query\=/ ) {
				$total_result++;
			}
			print OUTFILE $line;
		}
		close(INFILE);
	}
	close(OUTFILE);
	close(DIR);

	#	system("rm -rf $OUTPUT_DIR");

	print STDERR "done.\n";
	print STDERR "Total result: $total_result\n";

}

#if ($composite_output) {
#    print STDERR "Collating output ...";
#    opendir( DIR, $OUTPUT_DIR ) or die "Can't open $OUTPUT_DIR\n";
#
#    if ( $opt{o} =~ /\.bz2$/ ) {
#        open( OUTFILE, "|pbzip2 -c -9 >$opt{o}" ) || die "Can't open $opt{o}\n";
#    }
#    elsif ( $opt{o} =~ /\.gz$/ ) {
#        open( OUTFILE, "|gzip -c -9 >$opt{o}" ) || die "Can't open $opt{o}\n";
#    }
#    else {
#        open( OUTFILE, ">$opt{o}" ) || die "Can't open $opt{o}\n";
#    }
#
#    while ( defined( $filename = readdir(DIR) ) ) {
#
#        my $infile = $OUTPUT_DIR . '/' . $filename;
#        next if ( -d $infile );
#
#        if ( $infile =~ /\.hmmscan\.out$/ ) {
#
#            #		print STDERR $infile, "\n";
#            $total_returned_job++;
#
#           #open( INFILE, "gunzip  -c $infile|" ) || die "Can't open $infile\n";
#            open( INFILE, $infile ) || die "Can't open $infile\n";
#
#            while ( my $line = <INFILE> ) {
#                if ( $line =~ /^\#/ ) {
#                    next if $header_read;
#                    print OUTFILE $line;
#                    ++$header_line_count;
#
#                    if ( $header_line_count == 3 ) {
#                        $header_read = 1;
#
#                    }
#                    next;
#                }
#                my @f = split( /\s+/, $line );
#
#                unless ( exists $queries{ $f[3] } ) {
#                    $queries{ $f[3] } = 1;
#                    $total_result++;
#                }
#
#                #			if ( $line =~ /^Query\=/ ) {
#                #				$total_result++;
#                #			}
#                print OUTFILE $line;
#            }
#            close(INFILE);
#        }
#        elsif ( $infile =~ /\.missing.count$/ ) {
#            open( INFILE, $infile ) || die "Can't open $infile\n";
#
#            while ( my $line = <INFILE> ) {
#                chomp $line;
#                $line =~ s/^\s+//;
#                $line =~ s/\s+$//;
#                my @f = split( /\s+/, $line );
#
#                if ( @f != 3 ) {
#                    die "Something went wrong, cann't parse $infile\n";
#                }
#                $missing_count += $f[0];
#            }
#            close(INFILE);
#        }
#        else { next; }
#    }
#    close(OUTFILE);
#    close(DIR);
#
#    #	system("rm -rf $OUTPUT_DIR");
#
#    print STDERR "done.\n";
#    print STDERR "Total result: $total_result\n";
#
#}

print STDERR "Total returned jobs: $total_returned_job\n";
print STDERR "Total jobs: $total_job\n";
print STDERR "No hit proteins: $missing_count\n";

if (   $total_job == $total_returned_job
    && $total_seq == ( $missing_count + $total_result ) )
{
    print STDERR "All seems well :-) Removing temp files\n";
    system("rm -rf $LOG_DIR") == 0 || die "Can't remove $LOG_DIR\n";

    if ($composite_input) {
        system("rm -rf $TEMP_DIR") == 0 || die "Can't remove $TEMP_DIR\n";
    }

    if ($composite_output) {
        system("rm -rf $OUTPUT_DIR") == 0 || die "Can't remove $OUTPUT_DIR\n";
    }
}
else {
    die "ERROR: Some problems in running\n";
}

exit 0;

sub gotosleep {
    my $process_num = shift;

    if ( $process_num == 0 ) {
        print STDERR "Waiting for the jobs to finish...\n";
    }
    else {
        print STDERR "Process limit has reached...waiting\n";
    }

    while (1) {

        #		if ( $process_num == 0 ) {
        #
        #		} else {
        #
        #			print STDERR "Process limit has reached...waiting\n";
        #		}
        my %status;
        my %machine;
        my $jobstat = 'qstat |';

        if ( $engine eq "LSF" ) {
            $jobstat = "bjobs -a |";
        }
        open( PIPE, $jobstat );

        while ( my $line = <PIPE> ) {
            chomp $line;

            if ( $line =~ /^JOBID/ || $line =~ /^job-ID/i || $line =~ /^-/ ) {
                next;
            }
            $line =~ s/^\s+//;
            $line =~ s/\s+$//;

            my @fields = split( /\s+/, $line );
            if ( $engine eq "LSF" ) {
                $status{ $fields[0] } = $fields[2];

                if ( $fields[5] =~ /(\S+)\.nc/ ) {
                    $machine{ $fields[0] } = $1;
                }
            }
            elsif ( $engine eq "SGE" ) {
                $status{ $fields[0] } = $fields[4];

                if ( defined( $fields[8] ) && $fields[8] =~ /\@(\S+)/ ) {
                    $machine{ $fields[1] } = $1;
                }
            }
            else {

            }
        }

        close(PIPE);

        my $running = 0;
        my $waiting = 0;

        for ( my $i = 0; $i < @jobs; $i++ ) {

            #while (	my $pid = shift @jobs) {
            my $pid = shift @jobs;

            if (   !defined( $status{$pid} )
                || $status{$pid} eq "DONE"
                || $status{$pid} eq "EXIT" )
            {
                delete( $time{$pid} );
                my $file = $pid_2_filename{$pid};
                delete( $pid_2_filename{$pid} );

                #delete_file ($file);

            }
            else {
                my $current_time = time();
                my $start_time   = $time{$pid};

                if ( $status{$pid} eq "PEND"
                    && ( $current_time - $start_time ) > 1800 )
                {
                    system("bkill $pid");

                    #$excluded_machines[@excluded_machines] = $machine{$pid};
                    delete( $time{$pid} );
                    my $file = $pid_2_filename{$pid};
                    print STDERR "Restarting job $file...\n";
                    delete( $pid_2_filename{$pid} );
                    $total_job--;
                    launch_job($file);

                }
                elsif (( $status{$pid} eq "RUN" )
                    && ( ( $current_time - $start_time ) > 1800 ) )
                {
                    system("bkill $pid");

                    if ( exists $machine{$pid} ) {
                        $excluded_machines[@excluded_machines] = $machine{$pid};
                    }
                    delete( $time{$pid} );
                    my $file = $pid_2_filename{$pid};
                    print STDERR "Restarting job $file...\n";
                    $total_job--;
                    delete( $pid_2_filename{$pid} );
                    launch_job($file);

                }

                else {
                    $running++ if ( $status{$pid} eq "r" );
                    $waiting++
                        if ( $status{$pid} eq "w" || $status{$pid} eq "qw" );
                    push @jobs, $pid;
                }
            }

        }

        if ( @jobs <= $process_num ) {
            my $num_jobs = scalar(@jobs);
            print STDERR
                "Num of jobs: $num_jobs running=$running waiting=$waiting returning\n";
            return 0;
        }
        else {
            my $num_jobs = scalar(@jobs);
            print STDERR
                "Num of jobs=$num_jobs running=$running waiting=$waiting \n";
            sleep 5;
        }
    }
}

sub get_base_name {
    my $filename = shift;
    $filename =~ /^(\S+)\.[.]*?/;
    return $1;

}

sub delete_file {
    my $filename = shift;
    my $file     = $CURRENT_DIR . '/' . $filename;
    unlink($file);
}

sub launch_job {
	my $filename = shift;
	my $basename = get_base_name($filename);
	my $logfile  = $LOG_DIR . '/' . $basename . '.log';
	my $outfile  = $OUTPUT_DIR . '/' . $basename . '.bla.gz';
	my $infile   = $TEMP_DIR . '/' . $filename;
	print STDERR "Scheduling jobs for $filename...";

	my $lsf_options = $LSF_OPTIONS;

	if (@excluded_machines) {
		my $s = join( " ", @excluded_machines );
		print STDERR "Excluding $s from the machine list...\n";
		$lsf_options .= ' -m "' . $s . ' others+2"';

	}
	open( LSF,

		#"$LSF $lsf_options -o $logfile $BLAST $OPTIONS -i $infile -o $outfile|"
"$LSF $lsf_options -o $logfile \"$BLAST $OPTIONS -i $infile | gzip -c >$outfile\" |"
	);
	$total_job++;
	while ( my $line = <LSF> ) {
		if ( $engine eq "LSF" ) {
			if ( $line =~ /\<(\S+)\>/ ) {
				$jobs[@jobs]        = $1;
				$pid_2_filename{$1} = $filename;
				$time{$1}           = time();

			}
			else {
				close LSF;
				die "Can't schedule job\n";
			}
		}		
		elsif ( $engine eq "SGE" ) {
			if ( $line =~ /Your\s+job\s+(\d+)\s+/ ) {
				$jobs[@jobs]        = $1;
				$pid_2_filename{$1} = $filename;
				$time{$1}           = time();
			}
			else {
				close LSF;
				die "Can't schedule job\n";
			}
		}
		else {

		}
	}
	print STDERR "done\n";
	close(LSF);

}

#sub launch_job {
#    my $filename    = shift;
#    my $basename    = get_base_name($filename);
#    my $logfile     = $LOG_DIR . '/' . $basename . '.log';
#    my $outfile     = $OUTPUT_DIR . '/' . $basename . '.hmmscan.out';
#    my $infile      = $TEMP_DIR . '/' . $filename;
#    my $missing_out = $OUTPUT_DIR . '/' . $basename . '.missing.count';
#    print STDERR "Scheduling jobs for $filename...";
#
#    my $lsf_options = $LSF_OPTIONS;
#
#    if (@excluded_machines) {
#        my $s = join( " ", @excluded_machines );
#        print STDERR "Excluding $s from the machine list...\n";
#        $lsf_options .= ' -m "' . $s . ' others+2"';
#
#    }
#
##print STDERR "$LSF $lsf_options -o $logfile $BLAST $OPTIONS --domtblout $outfile
##    $database $infile \| grep -i \"No hits detected\"\|wc >$missing_out |";
#	my $lsf_command = "$LSF $lsf_options -o $logfile \'$BLAST $OPTIONS --domtblout $outfile $database $infile \| grep \"No hits detected\"\|wc >$missing_out\' |";
#	open( LSF,
#        #"$LSF $lsf_options -o $logfile $BLAST $OPTIONS -i $infile -o $outfile|"
#        #"$LSF $lsf_options -o $logfile \'$BLAST $OPTIONS --domtblout $outfile \
#        #$database $infile \| grep \"No hits detected\"\|wc >$missing_out\' |"
#		  $lsf_command		);
#    $total_job++;
#
#    while ( my $line = <LSF> ) {
#        if ( $engine eq "LSF" ) {
#
#            if ( $line =~ /\<(\S+)\>/ ) {
#                $jobs[@jobs]        = $1;
#                $pid_2_filename{$1} = $filename;
#                $time{$1}           = time();
#
#            }
#            else {
#                close LSF;
#                die "Can't schedule job\n";
#            }
#        }
#        elsif ( $engine eq "SGE" ) {
#
#            if ( $line =~ /Your\s+job\s+(\d+)\s+/ ) {
#                $jobs[@jobs]        = $1;
#                $pid_2_filename{$1} = $filename;
#                $time{$1}           = time();
#            }
#            else {
#                close LSF;
#                die "Can't schedule job\n";
#            }
#        }
#        else {
#
#        }
#    }
#    print STDERR "done\n";
#    close(LSF);
#
#}

sub open_file {
    my $filename = shift;
    unless ( -f $filename ) { die "Could not find $filename\n" }
    my $fh;

    if ( $filename =~ /\.bz2$/ ) {

        if ( check_exists("pbzip2") ) {
            open( $fh, "pbzip2 -dc $filename|" )
                || die "Can't open $filename\n";
        }
        elsif ( check_exists("bzip2") ) {
            open( $fh, "bzip2 -dc $filename|" ) || die "Can't open $filename\n";

        }
        else {
            die "Could not find bzip2 or pbzip2 in path\n";
        }

    }
    elsif ( $filename =~ /\.gz$/ ) {

        if ( check_exists("pigz") ) {
            open( $fh, "pigz -dc $filename|" ) || die "Can't open $filename\n";
        }
        elsif ( check_exists("gzip") ) {
            open( $fh, "gzip -dc $filename|" )
                || die "Can't open $filename\n";
        }
        else {
            die "Could not find pigz or gzip in the path\n";
        }

    }
    else {
        open( $fh, "$filename" ) || die "Can't open $filename\n";
    }

    return $fh;
}

sub check_exists {
    my $command = shift;

    if ( system("which $command > /dev/null") == 0 ) {
        return 1;
    }
    else {
        return 0;
    }
}
