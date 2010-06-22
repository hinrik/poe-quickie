package POE::Quickie;

use strict;
use warnings;
use Carp;
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
                exception
                create_wheel
                delete_wheel
                child_signal
                child_closed
                child_timeout
                child_stdout
                child_stderr
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
    return $poe_kernel->call($self->{session_id}, 'create_wheel', \%args);
}

sub create_wheel {
    my ($kernel, $self, $args) = @_[KERNEL, OBJECT, ARG0];

    my $wheel;
    eval {
        $wheel = POE::Wheel::Run->new(
            CloseEvent  => 'child_closed',
            StdoutEvent => 'child_stdout',
            StderrEvent => 'child_stderr',
            Program     => $args->{Program},
            (defined $args->{ProgramArgs}
                ? (ProgramArgs => $args->{ProgramArgs})
                : ()
            ),
            (ref $args->{Program} eq 'CODE' && $^O eq 'Win32'
                ? (CloseOnCall => 1)
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
            = $kernel->delay_set('child_timeout', $args->{timeout}, $wheel->ID);
    }
    $kernel->sig_child($wheel->PID, 'child_signal');

    return $wheel->ID;
}

sub _start {
    my ($kernel, $session, $self) = @_[KERNEL, SESSION, OBJECT];

    my $session_id = $session->ID;
    $self->{session_id} = $session_id;
    $kernel->sig(DIE => 'exception');
    $kernel->refcount_increment($session_id, __PACKAGE__);
    return;
}

sub exception {
    my ($kernel, $self, $ex) = @_[KERNEL, OBJECT, ARG1];
    chomp $ex->{error_str};
    warn "Event $ex->{event} in session "
        .$ex->{dest_session}->ID." raised exception:\n  $ex->{error_str}\n";
    $kernel->sig_handled();
    return;
}

sub child_signal {
    my ($kernel, $self, $pid, $status) = @_[KERNEL, OBJECT, ARG1, ARG2];
    my $id = $self->_pid_to_id($pid);

    my $event = $self->{wheels}{$id}{args}{ExitEvent};
    $kernel->post($self->{parent_id}, $event, $status) if defined $event;
    $kernel->yield('delete_wheel', $id);
    return;
}

sub child_closed {
    my ($kernel, $self, $id) = @_[KERNEL, OBJECT, ARG0];
    $kernel->yield('delete_wheel', $id);
    return;
}

sub child_timeout {
    my ($self, $id) = @_[OBJECT, ARG0];
    $self->{wheels}{$id}->kill();
    return;
}

sub child_stdout {
    my ($kernel, $self, $output, $id) = @_[KERNEL, OBJECT, ARG0, ARG1];

    if (!exists $self->{wheels}{$id}{args}{StdoutEvent}) {
        print "$output\n";
    }
    elsif (defined (my $event = $self->{wheels}{$id}{args}{StdoutEvent})) {
        $kernel->post($self->{parent_id}, $event, $output, $id);
    }

    return;
}

sub child_stderr {
    my ($kernel, $self, $error, $id) = @_[KERNEL, OBJECT, ARG0, ARG1];

    if (!exists $self->{wheels}{$id}{args}{StderrEvent}) {
        warn "$error\n";
    }
    elsif (defined (my $event = $self->{wheels}{$id}{args}{StderrEvent})) {
        $kernel->post($self->{parent_id}, $event, $error, $id);
    }

    return;
}

# only delete the wheel after both child_signal and child_closed
# have called this
sub delete_wheel {
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

=head1 NAME

POE::Quickie - A lazy way to execute programs

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

This method starts a new program. It takes the following parameters

B<'Program'> (required), which will be passed to
L<POE::Wheel::Run|POE::Wheel::Run>'s constructor.

B<'Program_args'> (optional), same as above.

B<'Timeout'> (optional), a timeout in seconds after which the program will
be forcibly killed if it is still running.

B<'StdoutEvent'> (optional), same as the epynomous parameter to POE::Wheel::Run.

B<'StderrEvent'> (optional), same as the epynomous parameter to POE::Wheel::Run.

=head1 AUTHOR

Hinrik E<Ouml>rn SigurE<eth>sson, hinrik.sig@gmail.com

=head1 LICENSE AND COPYRIGHT

Copyright 2010 Hinrik E<Ouml>rn SigurE<eth>sson

This program is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
