import XCTest
@testable import CockpitDev

final class ValidatorsTests: CockpitDevTestCase {

    // MARK: - Workspace Name Validation

    func testWorkspaceName_validSimpleName_returnsValid() {
        let result = Validators.validateWorkspaceName("My Project")
        XCTAssertTrue(result.isValid)
        XCTAssertNil(result.errorMessage)
    }

    func testWorkspaceName_validWithHyphensAndUnderscores_returnsValid() {
        let result = Validators.validateWorkspaceName("my-project_2024")
        XCTAssertTrue(result.isValid)
    }

    func testWorkspaceName_validSingleCharacter_returnsValid() {
        let result = Validators.validateWorkspaceName("A")
        XCTAssertTrue(result.isValid)
    }

    func testWorkspaceName_validExactlyMaxLength_returnsValid() {
        let name = String(repeating: "a", count: 100)
        let result = Validators.validateWorkspaceName(name)
        XCTAssertTrue(result.isValid)
    }

    func testWorkspaceName_empty_returnsInvalid() {
        let result = Validators.validateWorkspaceName("")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "Workspace name cannot be empty.")
    }

    func testWorkspaceName_exceedsMaxLength_returnsInvalid() {
        let name = String(repeating: "a", count: 101)
        let result = Validators.validateWorkspaceName(name)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage?.contains("100") ?? false)
    }

    func testWorkspaceName_disallowedSpecialCharacters_returnsInvalid() {
        let invalidNames = ["test@project", "hello#world", "foo/bar", "a.b", "test$", "name!", "a&b"]
        for name in invalidNames {
            let result = Validators.validateWorkspaceName(name)
            XCTAssertFalse(result.isValid, "Expected invalid for: \(name)")
            XCTAssertTrue(result.errorMessage?.contains("letters, numbers, spaces, hyphens, and underscores") ?? false)
        }
    }

    func testWorkspaceName_numbersOnly_returnsValid() {
        let result = Validators.validateWorkspaceName("12345")
        XCTAssertTrue(result.isValid)
    }

    func testWorkspaceName_spacesHyphensUnderscores_returnsValid() {
        let result = Validators.validateWorkspaceName("My Project - Phase_1")
        XCTAssertTrue(result.isValid)
    }

    // MARK: - Workspace Name Uniqueness

    func testWorkspaceNameUniqueness_noDuplicate_returnsValid() {
        let result = Validators.validateWorkspaceNameUniqueness("New Project", existingNames: ["Other Project"])
        XCTAssertTrue(result.isValid)
    }

    func testWorkspaceNameUniqueness_exactDuplicate_returnsInvalid() {
        let result = Validators.validateWorkspaceNameUniqueness("My Project", existingNames: ["My Project"])
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage?.contains("already exists") ?? false)
    }

    func testWorkspaceNameUniqueness_caseInsensitiveDuplicate_returnsInvalid() {
        let result = Validators.validateWorkspaceNameUniqueness("my project", existingNames: ["My Project"])
        XCTAssertFalse(result.isValid)
    }

    func testWorkspaceNameUniqueness_emptyExistingNames_returnsValid() {
        let result = Validators.validateWorkspaceNameUniqueness("Any Name", existingNames: [])
        XCTAssertTrue(result.isValid)
    }

    // MARK: - Sprint Date Validation

    func testSprintDates_startBeforeEnd_returnsValid() {
        let start = Date()
        let end = start.addingTimeInterval(86400) // +1 day
        let result = Validators.validateSprintDates(startDate: start, endDate: end)
        XCTAssertTrue(result.isValid)
    }

    func testSprintDates_startEqualsEnd_returnsInvalid() {
        let date = Date()
        let result = Validators.validateSprintDates(startDate: date, endDate: date)
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "Start date must be before end date.")
    }

    func testSprintDates_startAfterEnd_returnsInvalid() {
        let start = Date()
        let end = start.addingTimeInterval(-86400) // -1 day
        let result = Validators.validateSprintDates(startDate: start, endDate: end)
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "Start date must be before end date.")
    }

    func testSprintDates_oneSecondApart_returnsValid() {
        let start = Date()
        let end = start.addingTimeInterval(1) // +1 second
        let result = Validators.validateSprintDates(startDate: start, endDate: end)
        XCTAssertTrue(result.isValid)
    }

    // MARK: - Story Points Validation

    func testStoryPoints_validFibonacciValues_returnsValid() {
        let validValues = [1, 2, 3, 5, 8, 13, 21]
        for value in validValues {
            let result = Validators.validateStoryPoints(value)
            XCTAssertTrue(result.isValid, "Expected valid for: \(value)")
        }
    }

    func testStoryPoints_invalidValues_returnsInvalid() {
        let invalidValues = [0, 4, 6, 7, 9, 10, 11, 12, 14, 15, 20, 22, 100]
        for value in invalidValues {
            let result = Validators.validateStoryPoints(value)
            XCTAssertFalse(result.isValid, "Expected invalid for: \(value)")
        }
    }

    func testStoryPoints_negativeValue_returnsInvalid() {
        let result = Validators.validateStoryPoints(-1)
        XCTAssertFalse(result.isValid)
    }

    func testStoryPoints_invalidValue_errorContainsAllowedValues() {
        let result = Validators.validateStoryPoints(4)
        XCTAssertTrue(result.errorMessage?.contains("1, 2, 3, 5, 8, 13, 21") ?? false)
    }

    func testIsNonStandardStoryPoints_standardValue_returnsFalse() {
        XCTAssertFalse(Validators.isNonStandardStoryPoints(5))
    }

    func testIsNonStandardStoryPoints_nonStandardValue_returnsTrue() {
        XCTAssertTrue(Validators.isNonStandardStoryPoints(4))
        XCTAssertTrue(Validators.isNonStandardStoryPoints(10))
    }

    // MARK: - Commit Message Validation

    func testCommitMessage_validMessage_returnsValid() {
        let result = Validators.validateCommitMessage("Fix bug in login flow")
        XCTAssertTrue(result.isValid)
    }

    func testCommitMessage_singleCharacter_returnsValid() {
        let result = Validators.validateCommitMessage("x")
        XCTAssertTrue(result.isValid)
    }

    func testCommitMessage_exactlyMaxLength_returnsValid() {
        let message = String(repeating: "a", count: 500)
        let result = Validators.validateCommitMessage(message)
        XCTAssertTrue(result.isValid)
    }

    func testCommitMessage_empty_returnsInvalid() {
        let result = Validators.validateCommitMessage("")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "Commit message cannot be empty.")
    }

    func testCommitMessage_whitespaceOnly_returnsInvalid() {
        let result = Validators.validateCommitMessage("   \n\t  ")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "Commit message cannot be empty.")
    }

    func testCommitMessage_exceedsMaxLength_returnsInvalid() {
        let message = String(repeating: "a", count: 501)
        let result = Validators.validateCommitMessage(message)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage?.contains("500") ?? false)
    }

    func testCommitMessage_trimsWhitespaceBeforeValidation() {
        // Message with leading/trailing whitespace that is valid after trimming
        let message = "  Valid message  "
        let result = Validators.validateCommitMessage(message)
        XCTAssertTrue(result.isValid)
    }

    // MARK: - File Size Validation

    func testFileSize_zeroBytes_returnsValid() {
        let result = Validators.validateFileSize(0)
        XCTAssertTrue(result.isValid)
    }

    func testFileSize_underLimit_returnsValid() {
        let result = Validators.validateFileSize(50 * 1024 * 1024) // 50 MB
        XCTAssertTrue(result.isValid)
    }

    func testFileSize_exactlyAtLimit_returnsValid() {
        let result = Validators.validateFileSize(100 * 1024 * 1024) // 100 MB
        XCTAssertTrue(result.isValid)
    }

    func testFileSize_exceedsLimit_returnsInvalid() {
        let result = Validators.validateFileSize(100 * 1024 * 1024 + 1) // 100 MB + 1 byte
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage?.contains("100 MB") ?? false)
    }

    func testFileSize_negativeValue_returnsInvalid() {
        let result = Validators.validateFileSize(-1)
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "File size cannot be negative.")
    }

    func testFileSize_oneByte_returnsValid() {
        let result = Validators.validateFileSize(1)
        XCTAssertTrue(result.isValid)
    }

    // MARK: - Role Permission Checks

    func testCanManage_ownerRole_returnsTrue() {
        XCTAssertTrue(Validators.canManage(role: .owner))
    }

    func testCanManage_adminRole_returnsTrue() {
        XCTAssertTrue(Validators.canManage(role: .admin))
    }

    func testCanManage_memberRole_returnsFalse() {
        XCTAssertFalse(Validators.canManage(role: .member))
    }

    func testCanManage_viewerRole_returnsFalse() {
        XCTAssertFalse(Validators.canManage(role: .viewer))
    }

    func testValidateManagementPermission_owner_returnsValid() {
        let result = Validators.validateManagementPermission(role: .owner)
        XCTAssertTrue(result.isValid)
    }

    func testValidateManagementPermission_admin_returnsValid() {
        let result = Validators.validateManagementPermission(role: .admin)
        XCTAssertTrue(result.isValid)
    }

    func testValidateManagementPermission_member_returnsInvalid() {
        let result = Validators.validateManagementPermission(role: .member)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage?.contains("Insufficient permissions") ?? false)
    }

    func testValidateManagementPermission_viewer_returnsInvalid() {
        let result = Validators.validateManagementPermission(role: .viewer)
        XCTAssertFalse(result.isValid)
    }

    // MARK: - Role Change Validation

    func testRoleChange_ownerToAdmin_multipleOwners_returnsValid() {
        let result = Validators.validateRoleChange(currentRole: .owner, newRole: .admin, ownerCount: 2)
        XCTAssertTrue(result.isValid)
    }

    func testRoleChange_ownerToAdmin_lastOwner_returnsInvalid() {
        let result = Validators.validateRoleChange(currentRole: .owner, newRole: .admin, ownerCount: 1)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage?.contains("at least one Owner") ?? false)
    }

    func testRoleChange_ownerToMember_lastOwner_returnsInvalid() {
        let result = Validators.validateRoleChange(currentRole: .owner, newRole: .member, ownerCount: 1)
        XCTAssertFalse(result.isValid)
    }

    func testRoleChange_ownerToOwner_lastOwner_returnsValid() {
        // Changing owner to owner is a no-op, should be valid
        let result = Validators.validateRoleChange(currentRole: .owner, newRole: .owner, ownerCount: 1)
        XCTAssertTrue(result.isValid)
    }

    func testRoleChange_memberToAdmin_returnsValid() {
        let result = Validators.validateRoleChange(currentRole: .member, newRole: .admin, ownerCount: 1)
        XCTAssertTrue(result.isValid)
    }

    func testRoleChange_adminToMember_returnsValid() {
        let result = Validators.validateRoleChange(currentRole: .admin, newRole: .member, ownerCount: 1)
        XCTAssertTrue(result.isValid)
    }

    // MARK: - Modify Permission Validation

    func testModifyPermission_viewer_returnsInvalid() {
        let result = Validators.validateModifyPermission(role: .viewer)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage?.contains("Viewers") ?? false)
    }

    func testModifyPermission_member_returnsValid() {
        let result = Validators.validateModifyPermission(role: .member)
        XCTAssertTrue(result.isValid)
    }

    func testModifyPermission_admin_returnsValid() {
        let result = Validators.validateModifyPermission(role: .admin)
        XCTAssertTrue(result.isValid)
    }

    func testModifyPermission_owner_returnsValid() {
        let result = Validators.validateModifyPermission(role: .owner)
        XCTAssertTrue(result.isValid)
    }

    // MARK: - ValidationResult Equatable

    func testValidationResult_validEqualsValid() {
        XCTAssertEqual(Validators.ValidationResult.valid, Validators.ValidationResult.valid)
    }

    func testValidationResult_invalidEqualsInvalidWithSameMessage() {
        let a = Validators.ValidationResult.invalid("Error")
        let b = Validators.ValidationResult.invalid("Error")
        XCTAssertEqual(a, b)
    }

    func testValidationResult_invalidNotEqualWithDifferentMessage() {
        let a = Validators.ValidationResult.invalid("Error A")
        let b = Validators.ValidationResult.invalid("Error B")
        XCTAssertNotEqual(a, b)
    }

    func testValidationResult_validNotEqualInvalid() {
        let a = Validators.ValidationResult.valid
        let b = Validators.ValidationResult.invalid("Error")
        XCTAssertNotEqual(a, b)
    }
}
