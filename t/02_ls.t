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
        Program     => sub { print "foo\n" },
        StdoutEvent => 'stdout',
    );
}

sub stdout {
    my ($heap, $output) = @_[HEAP, ARG0];
    is($output, 'foo', 'Got stdout');
    
    $heap->{quickie}->run(
        Program     => sub { warn "bar\n" },
        StderrEvent => 'stderr',
    );
}

sub stderr {
    my ($heap, $error) = @_[HEAP, ARG0];
    is($error, 'bar', 'Got stderr');
    $heap->{quickie}->shutdown();
}
