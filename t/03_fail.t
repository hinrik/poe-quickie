use strict;
use warnings;
use POE;
use POE::Quickie;
use Test::More tests => 1;

POE::Session->create(
    package_states => [
        (__PACKAGE__) => [qw(
            _start
            exit
        )],
    ],
    options => { trace => 0 },
);

POE::Kernel->run;

sub _start {
    my $heap = $_[HEAP];

    $heap->{quickie} = POE::Quickie->new(trace => 0);
    $heap->{quickie}->run(
        Program   => sub { die },
        ExitEvent => 'exit',
    );
}

sub exit {
    my ($heap, $status) = @_[HEAP, ARG0];
    isnt(($status >> 8), 0, 'Got exit status');
    $heap->{quickie}->shutdown();
}
