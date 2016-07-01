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

contract FallbackFailer {
    function () {
        throw;
    }
}

contract UsingTime {
    // Using this allows override of the block timestamp in tests
    function getTime() public constant returns (uint) {
        return block.timestamp;
    }
}

contract UsingMath {
    function flat(uint x, uint y) internal returns (uint) {
        if (x > y) return x - y;
        else return 0;
    }
    function cumsum(uint[] array) internal returns (uint[]) {
        uint[] memory out = new uint[](array.length);
        out[0] = array[0];
        for (uint i = 1; i < array.length; i++) {
            out[i] = array[i] + out[i - 1];
        }
        return out;
    }
    function sum(uint[] array) internal returns (uint total) {
        total = 0;
        for (uint i = 0; i < array.length; i++) {
            total += array[i];
        }
    }
}
