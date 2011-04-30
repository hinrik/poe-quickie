use strict;
use warnings FATAL => 'all';
use POE;
use POE::Quickie;
use Test::More tests => 7;

POE::Session->create(
    package_states => [
        (__PACKAGE__) => [qw(
            _start
            result
        )],
    ],
);

POE::Kernel->run;

sub _start {
    $_[HEAP]{pid} = quickie_run(
        ResultEvent => 'result',
        Context     => { a => 'b' },
        Program     => sub {
            print STDOUT "FOO\n";
            print STDERR "BAR\n";
        },
    );
}

sub result {
    my ($heap, $pid, $stdout, $stderr, $merged, $status, $context)
        = @_[HEAP, ARG0..$#_];

    is($pid, $heap->{pid}, 'Correct pid');
    is($stdout, "FOO\n", 'Got stdout');
    is($stderr, "BAR\n", 'Got stderr');
    like($merged, qr/FOO\n/m, 'Got merged stdout');
    like($merged, qr/FOO\n/m, 'Got merged stderr');
    is(($status >> 8), 0, 'Correct exit status');
    is($context->{a}, 'b', 'Correct context');
}
