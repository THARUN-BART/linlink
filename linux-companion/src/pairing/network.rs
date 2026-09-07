use std::net::UdpSocket;

/// Detect the machine's primary local LAN IP address by querying the routing table
/// using a dummy UDP connect (does not transmit any packets).
pub fn detect_local_ip() -> Option<String> {
    let socket = UdpSocket::bind("0.0.0.0:0").ok()?;
    socket.connect("8.8.8.8:80").ok()?;
    let local_addr = socket.local_addr().ok()?;
    let ip = local_addr.ip();
    if !ip.is_loopback() && !ip.is_unspecified() {
        Some(ip.to_string())
    } else {
        None
    }
}
