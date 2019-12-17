package App::IDA::Daemon::Link::SplitIDA;

# quick note here...
#
# One of the differences between this class and Link::Stripe is that
# we need to prepend a sharefile header to the output streams. Rather
# than implementing a complex check (with flags and buffers and
# whatnot) in the main split_process method, we can simply write the
# headers into the existing output buffer matrix during object
# construction.
#
# I'll need to bear this in mind when I write the generic greedy
# processing loop in +Split.
#
 
