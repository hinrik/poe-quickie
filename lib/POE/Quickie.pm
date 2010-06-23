package POE::Quickie;

use strict;
use warnings;
use Carp 'croak';
use POE;
use POE::Wheel::Run;

sub new {
    my ($package, %args) = @_;

    my $self = bless \%args, $package;
    $self->{parent_id} = POE::Kernel->get_active_session->ID;

    POE::Session->create(
        object_states => [
            $self => [qw(
                _start
                _exception
                _create_wheel
                _delete_wheel
                _child_signal
                _child_closed
                _child_timeout
                _child_stdout
                _child_stderr
                _shutdown
            )],
        ],
        options => {
            ($self->{debug}   ? (debug   => 1) : ()),
            ($self->{default} ? (default => 1) : ()),
            ($self->{trace}   ? (trace   => 1) : ()),
        },
    );

    return $self;
}

sub run {
    my ($self, %args) = @_;

    croak 'Program parameter not supplied' if !defined $args{Program};

    if ($args{Copy_inc} && ref $args{Program}) {
        croak 'Program must be a string when Copy_inc is enabled';
    }

    return $poe_kernel->call($self->{session_id}, '_create_wheel', \%args);
}

sub _create_wheel {
    my ($kernel, $self, $args) = @_[KERNEL, OBJECT, ARG0];

    my $program = $args->{Program};
    if ($args->{Copy_inc}) {
        my @inc = map { +'-I' => $_ } @INC;
        $program = [$^X, @inc, '-e', $program],
    }

    my $wheel;
    eval {
        $wheel = POE::Wheel::Run->new(
            CloseEvent  => '_child_closed',
            StdoutEvent => '_child_stdout',
            StderrEvent => '_child_stderr',
            Program     => $program,
            (defined $args->{ProgramArgs}
                ? (ProgramArgs => $args->{ProgramArgs})
                : ()
            ),
            (ref $args->{Program} eq 'CODE' && $^O eq 'Win32'
                ? (CloseOnCall => 1)
                : ()
            ),
            (defined $args->{PWR_args}
                ? (%{ $args->{PWR_args })
                : ()
            ),
        );
    };

    if ($@) {
        chomp $@;
        warn $@, "\n";
        return;
    }

    $self->{wheels}{$wheel->ID}{obj} = $wheel;
    $self->{wheels}{$wheel->ID}{args} = $args;
    $self->{wheels}{$wheel->ID}{alive} = 2;

    if (defined $args->{Timeout}) {
        $self->{wheels}{$wheel->ID}{alrm}
            = $kernel->delay_set('_child_timeout', $args->{Timeout}, $wheel->ID);
    }
    $kernel->sig_child($wheel->PID, '_child_signal');

    return $wheel->ID;
}

sub _start {
    my ($kernel, $session, $self) = @_[KERNEL, SESSION, OBJECT];

    my $session_id = $session->ID;
    $self->{session_id} = $session_id;
    $kernel->sig(DIE => '_exception');
    $kernel->refcount_increment($session_id, __PACKAGE__);
    return;
}

sub _exception {
    my ($kernel, $self, $ex) = @_[KERNEL, OBJECT, ARG1];
    chomp $ex->{error_str};
    warn "Event $ex->{event} in session "
        .$ex->{dest_session}->ID." raised exception:\n  $ex->{error_str}\n";
    $kernel->sig_handled();
    return;
}

sub _child_signal {
    my ($kernel, $self, $pid, $status) = @_[KERNEL, OBJECT, ARG1, ARG2];
    my $id = $self->_pid_to_id($pid);

    my $event = $self->{wheels}{$id}{args}{ExitEvent};
    my $context = $self->{wheels}{$id}{args}{Context};

    if (defined $event) {
        $kernel->post(
            $self->{parent_id},
            $event,
            $status,
            $id,
            (defined $context ? $context : ()),
        );
    }
    $kernel->yield('_delete_wheel', $id);
    return;
}

sub _child_closed {
    my ($kernel, $self, $id) = @_[KERNEL, OBJECT, ARG0];
    $kernel->yield('_delete_wheel', $id);
    return;
}

sub _child_timeout {
    my ($self, $id) = @_[OBJECT, ARG0];
    $self->{wheels}{$id}{obj}->kill();
    return;
}

sub _child_stdout {
    my ($kernel, $self, $output, $id) = @_[KERNEL, OBJECT, ARG0, ARG1];

    if (!exists $self->{wheels}{$id}{args}{StdoutEvent}) {
        print "$output\n";
    }
    elsif (defined (my $event = $self->{wheels}{$id}{args}{StdoutEvent})) {
        my $context = $self->{wheels}{$id}{args}{Context};
        $kernel->post(
            $self->{parent_id},
            $event,
            $output,
            $id,
            (defined $context ? $context : ()),
        );
    }

    return;
}

sub _child_stderr {
    my ($kernel, $self, $error, $id) = @_[KERNEL, OBJECT, ARG0, ARG1];

    if (!exists $self->{wheels}{$id}{args}{StderrEvent}) {
        warn "$error\n";
    }
    elsif (defined (my $event = $self->{wheels}{$id}{args}{StderrEvent})) {
        my $context = $self->{wheels}{$id}{args}{Context};
        $kernel->post(
            $self->{parent_id},
            $event,
            $error,
            $id,
            $self->{wheels}{$id}{args}{ExitEvent},
        );
    }

    return;
}

# only delete the wheel after both child_signal and child_closed
# have called this
sub _delete_wheel {
    my ($kernel, $self, $id) = @_[KERNEL, OBJECT, ARG0];

    $self->{wheels}{$id}{alive}--;
    if ($self->{wheels}{$id}{alive} == 0) {
        $kernel->alarm_remove($self->{wheels}{$id}{alrm});
        delete $self->{wheels}{$id};
    }
    return;
}

sub _pid_to_id {
    my ($self, $pid) = @_;

    for my $id (keys %{ $self->{wheels} }) {
        return $id if $self->{wheels}{$id}{obj}->PID == $pid;
    }

    return;
}

sub shutdown {
    my ($self) = @_;
    $poe_kernel->call($self->{session_id}, '_shutdown');
    return;
}

sub _shutdown {
    my ($kernel, $self) = @_[KERNEL, OBJECT];

    $kernel->alarm_remove_all();

    for my $id (keys %{ $self->{wheels}}) {
        $self->{wheels}{$id}{obj}->kill();
    }

    $kernel->refcount_decrement($self->{session_id}, __PACKAGE__);
    return;
}

1;

=encoding utf8

=head1 NAME

POE::Quickie - A lazy way to wrap blocking programs

=head1 SYNOPSIS

 use POE::Quickie;

 sub handler {
     my $quicky = POE::Quickie->new();
     $quicky->run(
         Program     => ['foo', 'bar'];
         StdoutEvent => 'stdout',
     );
 }

 sub stdout {
     print "got output: $_[ARG0]\n";
 }

=head1 DESCRIPTION

This module takes care of running external programs for you. It manages the
wheels, reaps the child processes, and can kill programs after a specified
timeout if you want.

=head1 METHODS

=head2 C<new>

Constructs a POE::Quickie object. You'll want to hold on to it.

Takes 3 optional parameters: B<'debug'>, B<'default'>, and B<'trace'>. These
will be passed to the object's L<POE::Session|POE::Session> constructor. See
its documentation for details.

=head3 C<run>

This method starts a new program. It returns the id of the newly created
L<POE::Wheel::Run|POE::Wheel::Run>. It takes the following arguments:

B<'Program'> (required), will be passed to POE::Wheel::Run's constructor.

B<'Copy_inc'> (optional), if true, a new instance of the active Perl
interpreter (C<$^X>) will be launched with B<'Program'> (which must be a
string) as the code (I<-e>) argument, and the current C<@INC> passed as
include (I<-I>) arguments. Default is false.

B<'ProgramArgs'> (optional), same as the epynomous parameter to
POE::Wheel::Run.

B<'StdoutEvent'> (optional), the event for delivering lines from the
program's STDOUT. If you don't supply this, they will be printed to the main
program's STDOUT. To explicitly ignore it, set it to C<undef>.

B<'StderrEvent'> (optional), the event for delivering lines from the
program's STDERR. If you don't supply this, they will be printed to the main
program's STDERR. To explicitly ignore it, set it to C<undef>.

B<'ExitEvent'> (optional, the event to be called when the program has exited.

B<'Timeout'> (optional), a timeout in seconds after which the program will
be forcibly killed if it is still running.

B<'Context'> (optional), a variable which will be sent back to you with every event.

B<'PWR_args'> (optional), a hash reference of options which will be passed
verbatim to the underlying POE::Wheel::Run object's constructor. Possibly
useful if you want to change the input/output filters and such.

=head2 C<shutdown>

This shuts down the POE::Quickie instance. Any running jobs will be killed.

=head2 OUTPUT

The following events might get sent to your session. The names correspond
to the options to C<run|/run>.

=head2 StdoutEvent

=over 4

=item C<ARG0>: the chunk of STDOUT generated by the program

=item C<ARG1>: the id of the underlying POE::Wheel::Run

=item C<ARG2>: the context variable, if any

=back

=head2 StderrEvent

=over 4

=item C<ARG0>: the chunk of STDERR generated by the program

=item C<ARG1>: the id of the underlying POE::Wheel::Run

=item C<ARG2>: the context variable, if any

=back

=head2 ExitEvent

=over 4

=item C<ARG0>: exit code produced by the program

=item C<ARG1>: the id of the underlying POE::Wheel::Run

=item C<ARG2>: the context variable, if any

=back

=head1 AUTHOR

Hinrik E<Ouml>rn SigurE<eth>sson, hinrik.sig@gmail.com

=head1 LICENSE AND COPYRIGHT

Copyright 2010 Hinrik E<Ouml>rn SigurE<eth>sson

This program is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
