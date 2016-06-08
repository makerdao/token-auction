contract Assertive {
    function assert(bool what) returns (bool) {
        if (!what) {
            throw;
        }
    }
    function assertIncreasing(uint[] array) {
        if (array.length < 2) return;

        for (uint i = 1; i < array.length; i ++) {
            assert(array[i] > array[i - 1]);
        }
    }
}
