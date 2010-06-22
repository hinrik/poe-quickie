use strict;
use warnings;
use POE;
use POE::Quickie;
use Test::More tests => 2;

POE::Session->create(
    package_states => [
        (__PACKAGE__) => [qw(
            _start
            stdout
            stderr
        )],
    ],
    options => { trace => 0 },
);

POE::Kernel->run;

sub _start {
    my $heap = $_[HEAP];

    $heap->{quickie} = POE::Quickie->new(trace => 0);
    $heap->{quickie}->run(
        Program     => ['ls', 'dist.ini'],
        StdoutEvent => 'stdout',
    );
}

sub stdout {
    my ($heap, $output) = @_[HEAP, ARG0];
    is($output, 'dist.ini', 'Got stdout');
    
    $heap->{quickie}->run(
        Program     => ['ls', 'dsfigjewgj0je3'],
        StderrEvent => 'stderr',
    );
}

sub stderr {
    my $heap = $_[HEAP];
    pass('Got stderr');
    $heap->{quickie}->shutdown();
}
