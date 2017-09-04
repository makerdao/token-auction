pragma solidity ^0.4.0;

contract Assertive {
    function assertIncreasing(uint[] array) internal {
        if (array.length < 2) return;

        for (uint i = 1; i < array.length; i ++) {
            assert(array[i] > array[i - 1]);
        }
    }
}

contract FallbackFailer {
    function () {
        require(false);
    }
}

contract TimeUser {
    // Using this allows override of the block timestamp in tests
    function getTime() public constant returns (uint) {
        return block.timestamp;
    }
}

contract MathUser {
    function zeroSub(uint x, uint y) internal returns (uint) {
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

contract SafeMathUser {
    // Safe math functions that throw on overflow.
    // These should be used anywhere that user input flows to.
    function safeMul(uint a, uint b) internal returns (uint c) {
        c = a * b;
        if (a != 0 && c / a != b) throw;
    }
    function safeAdd(uint a, uint b) internal returns (uint c) {
        c = a + b;
        if (c < a) throw;
    }
    function safeSub(uint a, uint b) internal returns (uint c) {
        if (b > a) throw;
        c = a - b;
    }
}

contract MutexUser {
    bool private mutex_lock;
    modifier exclusive {
        if (mutex_lock) throw;
        mutex_lock = true;
        _;
        mutex_lock = false;
    }
}
