define TPROXY_MARK = 0x1
define TPROXY_L4PROTO = { tcp, udp }
define TPROXY_PORT = 4444
define FAKEIP = { 198.18.0.0/15 }
define VOICELIST = {
  {{voicelist,}}
}

chain tproxy_prerouting {
 type filter hook prerouting priority mangle; policy accept;
 meta nfproto ipv6 return
 ip daddr != $FAKEIP ip daddr != $VOICELIST return
 ip daddr $VOICELIST meta l4proto udp tproxy ip to :$TPROXY_PORT meta mark set $TPROXY_MARK accept
 ip daddr $FAKEIP meta l4proto $TPROXY_L4PROTO tproxy ip to :$TPROXY_PORT meta mark set $TPROXY_MARK accept
}

chain tproxy_output {
 type route hook output priority mangle; policy accept;
 meta nfproto ipv6 return
 ip daddr != $FAKEIP ip daddr != $VOICELIST return
 ip daddr $VOICELIST meta l4proto udp meta mark set $TPROXY_MARK
 ip daddr $FAKEIP meta l4proto $TPROXY_L4PROTO meta mark set $TPROXY_MARK
}
