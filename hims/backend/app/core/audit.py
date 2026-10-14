"""Write one row in audit_log (NFR-10).

Call write_audit() in the SAME transaction as the change.
Then the change and its audit row are saved together, or not at all (NFR-11).
"""
from sqlalchemy import text
from sqlalchemy.orm import Session


def write_audit(db: Session, entity_name: str, entity_id: int, action: str, performed_by: int,
                changed_field: str | None = None, old_value=None, new_value=None) -> None:
    """Example: write_audit(db, "app_user", 7, "UPDATE", user["app_user_id"], "role_id", 3, 4)"""
    db.execute(
        text("""
            INSERT INTO hims_dev.audit_log
                (entity_name, entity_id, action, changed_field, old_value, new_value, performed_by)
            VALUES (:entity_name, :entity_id, :action, :changed_field, :old_value, :new_value, :performed_by)
        """),
        {
            "entity_name": entity_name[:50],
            "entity_id": entity_id,
            "action": action[:30],
            "changed_field": None if changed_field is None else changed_field[:50],
            "old_value": None if old_value is None else str(old_value)[:255],
            "new_value": None if new_value is None else str(new_value)[:255],
            "performed_by": performed_by,
        },
    )
