contract Assertive {
    function assert(bool what) returns (bool) {
        if (!what) {
            throw;
        }
    }
}
