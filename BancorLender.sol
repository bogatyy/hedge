pragma solidity ^ 0.4.11;

import './BancorChanger.sol';


// This contract allows people to lend and borrow any ERC-20 tokens that follow
// the Bancor Protocol (i.e. are tradable on-chain).
// When providing a loan, the lender sets a collateralRatio, which is the safety
// margin above 100% collateral. For example, if collateralRatio = 10%, the
// lender can margin-call whenever the collateral value drops below 110% of the
// lended token value.
// That way, even if the lended token increases in value suddenly, there is a
// safety margin for the lender to recover their loan in full.

contract BancorLender {
  // A struct that represents an agreement between two parties to borrow BNT.
  // Offers to borrow are represented in the same struct, as unfinished
  // agreements.
  // TODO: incorporate premiums for the lenders.
  struct BorrowAgreement {
    address lender;
    address borrower;
    uint256 tokenAmount;
    uint256 collateralAmount;
    uint32 collateralRatio;  // Extra collateral, in integer percent.
    uint expiration;
  }

  IERC20Token constant public bancorToken =
      IERC20Token(0x1F573D6Fb3F13d689FF844B4cE37794d79a7FF1C);
  BancorChanger constant public bancorChanger =
      BancorChanger(0xb72A0Fa1E537c956DFca72711c468EfD81270468);
  BorrowAgreement[] public agreements;

  function isCollateralWithinMargin(
      uint256 tokenAmount, uint256 collateralAmount, uint32 collateralRatio)
  returns(bool) {
    IERC20Token etherToken = bancorChanger.getQuickBuyEtherToken();
    uint256 collateralInTokens =
        bancorChanger.getPurchaseReturn(etherToken, collateralAmount);
    uint256 minCollateral = tokenAmount * (100 + collateralRatio) / 100;
    return (collateralInTokens > minCollateral);
  }

  function offerToLend(
      uint256 _amount, uint256 _collataral_ratio, uint _expiration) {
    assert(bancorToken.transferFrom(msg.sender, this, _amount));
    BorrowAgreement agreement;
    agreement.lender = msg.sender;
    agreement.borrower = 0;
    agreement.tokenAmount = _amount;
    agreement.expiration = _expiration;
    agreements.push(agreement);
  }

  function takeOffer(uint _offerNumber) payable {
    assert(isCollateralWithinMargin(
        agreements[_offerNumber].tokenAmount, msg.value,
        agreements[_offerNumber].collateralRatio));
    assert(bancorToken.transferFrom(
        this, msg.sender, agreements[_offerNumber].tokenAmount));
    agreements[_offerNumber].borrower = msg.sender;
    agreements[_offerNumber].collateralAmount = msg.value;
  }

  function addCollateral(uint _offerNumber) payable {
    agreements[_offerNumber].collateralAmount += msg.value;
  }

  function returnLoan(uint _agreementNumber) {
    assert(msg.sender == agreements[_agreementNumber].borrower);
    assert(bancorToken.transferFrom(
        msg.sender, agreements[_agreementNumber].lender,
        agreements[_agreementNumber].tokenAmount));
    agreements[_agreementNumber].tokenAmount = 0;
  }

  function forceClose(uint _agreementNumber) {
    assert(agreements[_agreementNumber].tokenAmount > 0);
    bool marginCall = !isCollateralWithinMargin(
        agreements[_agreementNumber].tokenAmount,
        agreements[_agreementNumber].collateralAmount,
        agreements[_agreementNumber].collateralRatio);
    if (marginCall || now > agreements[_agreementNumber].expiration) {
      uint256 salvagedAmount =
          bancorChanger.quickBuy(agreements[_agreementNumber].collateralAmount);
      if (salvagedAmount >= agreements[_agreementNumber].tokenAmount) {
        // Good: the debt is returned in full.
        // Should be the majority of cases since we provide a safety margin
        // and the BNT price is continuous.
        assert(bancorToken.transfer(
            agreements[_agreementNumber].lender,
            agreements[_agreementNumber].tokenAmount));
        assert(bancorToken.transfer(
            agreements[_agreementNumber].borrower,
            salvagedAmount - agreements[_agreementNumber].tokenAmount));
      } else {
        // Bad: part of the debt is not returned.
        assert(bancorToken.transfer(
            agreements[_agreementNumber].lender, salvagedAmount));
      }
    }
  }
}

