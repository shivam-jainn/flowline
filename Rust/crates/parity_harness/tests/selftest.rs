#[test]
fn harness_loads_goldens_and_canonicalizes() {
    let session = parity_harness::load_golden("session.sample.json");
    assert!(session.contains("sess_00000001"));
    let again = parity_harness::canonical(&session);
    assert_eq!(parity_harness::canonical(&again), again);
    parity_harness::assert_parity(&session, "session.sample.json");
}
