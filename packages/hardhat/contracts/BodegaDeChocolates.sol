// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IMercadoSantaFe} from "./interfaces/IMercadoSantaFe.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Uncomment this line to use console.log
import "hardhat/console.sol";

/// @title Bodega de Chocolates - Vault that manages the available Pesos liquidity.
/// @author Centauri devs team ✨
contract BodegaDeChocolates is ERC4626, Ownable {

    using SafeERC20 for IERC20;

    IMercadoSantaFe public immutable mercado;
    bool public acceptingNewLoans;

    uint256 public availableAsset; // ready to be borrowed.
    uint256 public totalInCDP;     // lock in a loan, in pesos

    constructor(IERC20 _asset, address _owner)
        Ownable(_owner)
        ERC4626(_asset)
        ERC20("Mercado: USDC <> XOC alphaV1", "MSF0001") {
        acceptingNewLoans = true;
    }

    function totalAssets() public view override returns (uint256) {
        return availableAsset + totalInCDP;
    }

    /// Lending Pesos -------------------------------------------------------------------

    /** @dev See {IERC4626-deposit}. */
    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    /** @dev See {IERC4626-mint}. */
    function mint(uint256 shares, address receiver) public override returns (uint256) {
        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        }

        uint256 assets = previewMint(shares);
        _deposit(_msgSender(), receiver, assets, shares);

        return assets;
    }

    /// @dev Deposit/mint common workflow.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        // If _asset is ERC-777, `transferFrom` can trigger a reentrancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transferred and before the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth
        SafeERC20.safeTransferFrom(IERC20(asset()), caller, address(this), assets);
        _mint(receiver, shares);

        /// updating global state.
        availableAsset += assets;

        emit Deposit(caller, receiver, assets, shares);
    }

    function lend(address _to, uint256 _amount) external /* onlyValidMercado */ {
        availableAsset -= _amount;

        doTransferOut(asset(), _to, _amount); // send pesos
    }

    // withdraw is never that simple !
    // /// @dev Withdraw/redeem common workflow.
    // function _withdraw(
    //     address caller,
    //     address receiver,
    //     address owner,
    //     uint256 assets,
    //     uint256 shares
    // ) internal override {
    //     if (caller != owner) {
    //         _spendAllowance(owner, caller, shares);
    //     }

    //     // If _asset is ERC-777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
    //     // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
    //     // calls the vault, which is assumed not malicious.
    //     //
    //     // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
    //     // shares are burned and after the assets are transferred, which is a valid state.
    //     _burn(owner, shares);
    //     SafeERC20.safeTransfer(_asset, receiver, assets);

    //     emit Withdraw(caller, receiver, owner, assets, shares);
    // }

    //     /** @dev See {IERC4626-withdraw}. */
    // function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
    //     uint256 maxAssets = maxWithdraw(owner);
    //     if (assets > maxAssets) {
    //         revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
    //     }

    //     uint256 shares = previewWithdraw(assets);
    //     _withdraw(_msgSender(), receiver, owner, assets, shares);

    //     return shares;
    // }

    // /** @dev See {IERC4626-redeem}. */
    // function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
    //     uint256 maxShares = maxRedeem(owner);
    //     if (shares > maxShares) {
    //         revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
    //     }

    //     uint256 assets = previewRedeem(shares);
    //     _withdraw(_msgSender(), receiver, owner, assets, shares);

    //     return assets;
    // }

    function doTransferIn(address _asset, address _from, uint256 _amount) private {
        IERC20(_asset).safeTransferFrom(_from, address(this), _amount);
    }

    function doTransferOut(address _asset, address _to, uint256 _amount) private {
        IERC20(_asset).safeTransfer(_to, _amount);
    }

}