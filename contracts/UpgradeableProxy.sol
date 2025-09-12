// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract UpgradeableProxy {
    // EIP-1967
    bytes32 private constant IMPLEMENTATION_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    // EIP-1967
    bytes32 private constant PROXY_ADMIN_SLOT = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);

    event Upgraded(address indexed implementation);

    event ProxyAdminChanged(address indexed newProxyAdmin);

    constructor(address _implementation, address _admin, bytes memory _data) {
        _setImplementation(_implementation);
        _setProxyAdmin(_admin);

        if (_data.length > 0) {
            (bool ok,) = _implementation.delegatecall(_data);
            require(ok, "initialization failed");
        }
    }

    modifier onlyProxyAdmin() {
        require(msg.sender == _getProxyAdmin(), "not a proxy admin");
        _;
    }

    function _setImplementation(address _impl) internal {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            sstore(slot, _impl)
        }
    }

    function _getImplementation() internal view returns (address impl) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            impl := sload(slot)
        }
    }

    function _setProxyAdmin(address _admin) internal {
        bytes32 slot = PROXY_ADMIN_SLOT;
        assembly {
            sstore(slot, _admin)
        }
    }

    function _getProxyAdmin() internal view returns (address adm) {
        bytes32 slot = PROXY_ADMIN_SLOT;
        assembly {
            adm := sload(slot)
        }
    }

    function upgradeTo(address newImplementation) external onlyProxyAdmin {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    fallback() external payable {
        address impl = _getImplementation();
        require(impl != address(0), "missing implementation");

        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}
