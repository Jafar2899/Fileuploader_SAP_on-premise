CLASS zjm_cl_ui_handler DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    INTERFACES if_http_extension .
  PROTECTED SECTION.
  PRIVATE SECTION.
    "--- Helper Methods ---
    METHODS get_html
      RETURNING VALUE(rv_html) TYPE string.

    METHODS get_table_primary_keys
      IMPORTING iv_tablename TYPE string
      EXPORTING et_keys      TYPE stringtab
                ev_success   TYPE abap_bool.

    METHODS validate_table_exists
      IMPORTING iv_tablename TYPE string
      EXPORTING ev_exists    TYPE abap_bool
                ev_error_msg TYPE string.

    METHODS perform_upsert
      IMPORTING iv_tablename     TYPE string
                it_data          TYPE STANDARD TABLE
                it_key_fields    TYPE stringtab
      EXPORTING ev_success       TYPE abap_bool
                ev_msg           TYPE string
                ev_rows_affected TYPE i.

    METHODS perform_update
      IMPORTING iv_tablename     TYPE string
                it_data          TYPE STANDARD TABLE
                it_key_fields    TYPE stringtab
      EXPORTING ev_success       TYPE abap_bool
                ev_msg           TYPE string
                ev_rows_affected TYPE i.
ENDCLASS.



CLASS ZJM_CL_UI_HANDLER IMPLEMENTATION.


  METHOD if_http_extension~handle_request.
    DATA: lv_verb          TYPE string,
          lv_data          TYPE xstring,
          lv_json_data     TYPE string,
          lv_html          TYPE string,
          lv_tablename     TYPE string,
          lv_operation     TYPE string,
          lt_key_fields    TYPE stringtab,
          lt_data_tab      TYPE REF TO data,
          lv_exists        TYPE abap_bool,
          lv_error_msg     TYPE string,
          lv_success       TYPE abap_bool,
          lv_rows_affected TYPE i.

    FIELD-SYMBOLS: <lt_out> TYPE STANDARD TABLE.

    lv_verb = server->request->get_method( ).

    CASE lv_verb.
      WHEN 'GET'.
        " --- 1. DISPLAY THE UI ---
        lv_html = get_html( ). " Call the helper method below
        server->response->set_cdata( lv_html ).
        server->response->set_header_field( name = 'content-type' value = 'text/html' ).
        server->response->set_status( code = 200 reason = 'OK' ).

      WHEN 'POST'.
        TRY.
            "--- 1. Extract and Validate Table Name ---
            lv_tablename = server->request->get_header_field( name = 'X-Table-Name' ).
            IF lv_tablename IS INITIAL OR lv_tablename = ' '.
              lv_tablename = server->request->get_form_field( name = 'x-table-name' ).
            ENDIF.
            IF lv_tablename IS INITIAL OR lv_tablename = ' '.
              lv_tablename = server->request->get_form_field( name = 'slug' ).
            ENDIF.
            IF lv_tablename IS INITIAL OR lv_tablename = ' '.
              lv_tablename = server->request->get_header_field( name = 'slug' ).
            ENDIF.
            CONDENSE lv_tablename.

            IF lv_tablename IS INITIAL.
              server->response->set_status( code = 400 reason = 'Bad Request' ).
              server->response->set_cdata( '{"error":"Table name not provided. Use header ''x-table-name'' or form field ''slug''."}' ).
              RETURN.
            ENDIF.

            "--- 2. Validate Table Exists ---
            CALL METHOD validate_table_exists
              EXPORTING
                iv_tablename = lv_tablename
              IMPORTING
                ev_exists    = lv_exists
                ev_error_msg = lv_error_msg.

            IF lv_exists = abap_false.
              server->response->set_status( code = 404 reason = 'Not Found' ).
              server->response->set_cdata( '{"error":"Table ' && lv_tablename && ' not found or not accessible. ' && lv_error_msg && '"}' ).
              RETURN.
            ENDIF.

            "--- 3. Extract Operation Type ---
            "Default is APPEND, can be APPEND, REPLACE, UPDATE, or UPSERT
            lv_operation = server->request->get_header_field( name = 'X-Upload-Operation' ).
            IF lv_operation IS INITIAL OR lv_operation = ' '.
              lv_operation = server->request->get_form_field( name = 'x-upload-operation' ).
            ENDIF.
            CONDENSE lv_operation.
            IF lv_operation IS INITIAL.
              lv_operation = server->request->get_header_field( name = 'x-upload-option' ).
              IF lv_operation IS INITIAL OR lv_operation = ' '.
                lv_operation = server->request->get_form_field( name = 'x-upload-option' ).
              ENDIF.
              IF lv_operation = '1'.
                lv_operation = 'REPLACE'.
              ELSE.
                lv_operation = 'APPEND'.
              ENDIF.
            ENDIF.

            "--- 4. Get the File Content (JSON) ---
            lv_data = server->request->get_data( ).

            IF lv_data IS INITIAL.
              server->response->set_status( code = 400 reason = 'Bad Request' ).
              server->response->set_cdata( '{"error":"No data provided in request body."}' ).
              RETURN.
            ENDIF.

            "--- 5. Convert XSTRING to STRING ---
            DATA: lo_conv_ce TYPE REF TO cl_abap_conv_in_ce.
            lo_conv_ce = cl_abap_conv_in_ce=>create( input = lv_data ).
            lo_conv_ce->read( IMPORTING data = lv_json_data ).

            "--- 6. Create Dynamic Internal Table ---
            CREATE DATA lt_data_tab TYPE STANDARD TABLE OF (lv_tablename).
            ASSIGN lt_data_tab->* TO <lt_out>.

            "--- 7. Deserialize JSON to Internal Table ---
            /ui2/cl_json=>deserialize(
              EXPORTING
                json = lv_json_data
              CHANGING
                data = <lt_out>
            ).

            IF <lt_out> IS INITIAL.
              server->response->set_status( code = 400 reason = 'Bad Request' ).
              server->response->set_cdata( '{"error":"JSON deserialization resulted in empty dataset. Check JSON structure."}' ).
              RETURN.
            ENDIF.

            "--- 8. Get Primary Keys for the Table ---
            CALL METHOD get_table_primary_keys
              EXPORTING
                iv_tablename = lv_tablename
              IMPORTING
                et_keys      = lt_key_fields
                ev_success   = lv_success.

            "--- 9. Perform Database Operation Based on Operation Type ---
            CASE lv_operation.
              WHEN 'APPEND'.
                INSERT (lv_tablename) FROM TABLE <lt_out>.
                IF sy-subrc = 0.
                  lv_rows_affected = sy-dbcnt.
                  server->response->set_status( code = 201 reason = 'Created' ).
                  server->response->set_cdata(
                    '{"success":true,"operation":"APPEND","rowsAffected":' && lv_rows_affected && ',"message":"' && lv_rows_affected && ' rows inserted into ' && lv_tablename && '"}'
                  ).
                ELSE.
                  server->response->set_status( code = 500 reason = 'Insert Failed' ).
                  server->response->set_cdata(
                    '{"error":"Failed to insert rows into ' && lv_tablename && '. Return code: ' && sy-subrc && '"}'
                  ).
                ENDIF.

              WHEN 'REPLACE'.
                DELETE FROM (lv_tablename).
                INSERT (lv_tablename) FROM TABLE <lt_out>.
                IF sy-subrc = 0.
                  lv_rows_affected = sy-dbcnt.
                  server->response->set_status( code = 201 reason = 'Created' ).
                  server->response->set_cdata(
                    '{"success":true,"operation":"REPLACE","rowsAffected":' && lv_rows_affected && ',"message":"Table cleared and ' && lv_rows_affected && ' rows inserted into ' && lv_tablename && '"}'
                  ).
                ELSE.
                  server->response->set_status( code = 500 reason = 'Replace Failed' ).
                  server->response->set_cdata(
                    '{"error":"Failed to replace data in ' && lv_tablename && '. Return code: ' && sy-subrc && '"}'
                  ).
                ENDIF.

              WHEN 'UPDATE'.
                IF lt_key_fields IS INITIAL.
                  server->response->set_status( code = 400 reason = 'Bad Request' ).
                  server->response->set_cdata(
                    '{"error":"UPDATE operation requires primary keys. Table ' && lv_tablename && ' has no keys defined."}'
                  ).
                ELSE.
                  CALL METHOD perform_update
                    EXPORTING
                      iv_tablename     = lv_tablename
                      it_data          = <lt_out>
                      it_key_fields    = lt_key_fields
                    IMPORTING
                      ev_success       = lv_success
                      ev_msg           = lv_error_msg
                      ev_rows_affected = lv_rows_affected.

                  IF lv_success = abap_true.
                    server->response->set_status( code = 200 reason = 'OK' ).
                    server->response->set_cdata(
                      '{"success":true,"operation":"UPDATE","rowsAffected":' && lv_rows_affected && ',"message":"' && lv_rows_affected && ' rows updated in ' && lv_tablename && '"}'
                    ).
                  ELSE.
                    server->response->set_status( code = 500 reason = 'Update Failed' ).
                    server->response->set_cdata(
                      '{"error":"' && lv_error_msg && '"}'
                    ).
                  ENDIF.
                ENDIF.

              WHEN 'UPSERT'.
                IF lt_key_fields IS INITIAL.
                  server->response->set_status( code = 400 reason = 'Bad Request' ).
                  server->response->set_cdata(
                    '{"error":"UPSERT operation requires primary keys. Table ' && lv_tablename && ' has no keys defined."}'
                  ).
                ELSE.
                  CALL METHOD perform_upsert
                    EXPORTING
                      iv_tablename     = lv_tablename
                      it_data          = <lt_out>
                      it_key_fields    = lt_key_fields
                    IMPORTING
                      ev_success       = lv_success
                      ev_msg           = lv_error_msg
                      ev_rows_affected = lv_rows_affected.

                  IF lv_success = abap_true.
                    server->response->set_status( code = 200 reason = 'OK' ).
                    server->response->set_cdata(
                      '{"success":true,"operation":"UPSERT","rowsAffected":' && lv_rows_affected && ',"message":"' && lv_rows_affected && ' rows inserted or updated in ' && lv_tablename && '"}'
                    ).
                  ELSE.
                    server->response->set_status( code = 500 reason = 'Upsert Failed' ).
                    server->response->set_cdata(
                      '{"error":"' && lv_error_msg && '"}'
                    ).
                  ENDIF.
                ENDIF.

              WHEN OTHERS.
                server->response->set_status( code = 400 reason = 'Bad Request' ).
                server->response->set_cdata(
                  '{"error":"Invalid operation: ' && lv_operation && '. Allowed: APPEND, REPLACE, UPDATE, UPSERT."}'
                ).
            ENDCASE.

          CATCH cx_root INTO DATA(lx_err).
            server->response->set_status( code = 500 reason = 'Server Error' ).
            server->response->set_cdata(
              '{"error":"Unexpected error during processing: ' && lx_err->get_text( ) && '"}'
            ).
        ENDTRY.
    ENDCASE.
  ENDMETHOD.


  METHOD get_html.
    DATA(nl) = cl_abap_char_utilities=>newline.

    rv_html =
      |<!DOCTYPE HTML> \n| &&
      |<html> \n| &&
      |<head> \n| &&
      |    <meta http-equiv="X-UA-Compatible" content="IE=edge"> \n| &&
      |    <meta http-equiv='Content-Type' content='text/html;charset=UTF-8' /> \n| &&
      |    <title>ABAP File Uploader</title> \n| &&
      |    <script id="sap-ui-bootstrap" src="https://sapui5.hana.ondemand.com/resources/sap-ui-core.js" \n| &&
      |        data-sap-ui-theme="sap_fiori_3_dark" data-sap-ui-xx-bindingSyntax="complex" data-sap-ui-compatVersion="edge" \n| &&
      |        data-sap-ui-async="true"> \n| &&
      |    </script> \n| &&
      |    <script> \n| &&
      |        sap.ui.require(['sap/ui/core/Core', 'sap/ui/unified/FileUploaderParameter', 'sap/m/MessageBox'], (oCore, FileUploaderParameter, MessageBox) => \{ \n| &&
      | \n| &&
      |            sap.ui.getCore().loadLibrary("sap.f", \{ \n| &&
      |                async: true \n| &&
      |            \}).then(() => \{ \n| &&
      |                let shell = new sap.f.ShellBar("shell") \n| &&
      |                shell.setTitle("ABAP File Uploader") \n| &&
      |                shell.placeAt("uiArea") \n| &&
      |                sap.ui.getCore().loadLibrary("sap.ui.layout", \{ \n| &&
      |                    async: true \n| &&
      |                \}).then(() => \{ \n| &&
      |                    let layout = new sap.ui.layout.VerticalLayout("layout") \n| &&
      |                    layout.placeAt("uiArea") \n| &&
      |                    let line2 = new sap.ui.layout.HorizontalLayout("line2") \n| &&
      |                    let line3 = new sap.ui.layout.HorizontalLayout("line3") \n| &&
      |                    let line4 = new sap.ui.layout.HorizontalLayout("line4") \n| &&
      |                    sap.ui.getCore().loadLibrary("sap.m", \{ \n| &&
      |                        async: true \n| &&
      |                    \}).then(() => \{\}) \n| &&
      |                    let button = new sap.m.Button("button") \n| &&
      |                    button.setText("Upload File") \n| &&
      |                    button.setType("Emphasized") \n| &&
      |                    button.attachPress(function () \{ \n| &&
      |                        let oFileUploader = oCore.byId("fileToUpload") \n| &&
      |                        let oInput = oCore.byId("tablename") \n| &&
      |                        let oGroup = oCore.byId("grpDataOptions") \n| &&
      | \n| &&
      |                        if (!oFileUploader.getValue()) \{ \n| &&
      |                            sap.m.MessageToast.show("Choose a file first") \n| &&
      |                            return \n| &&
      |                        \} \n| &&
      |                        if (!oInput.getValue())\{ \n| &&
      |                            sap.m.MessageToast.show("Target Table is Required") \n| &&
      |                            return \n| &&
      |                        \} \n| &&
      | \n| &&
      |                        oFileUploader.removeAllHeaderParameters(); \n| &&
      | \n| &&
      |                        oFileUploader.addHeaderParameter(new sap.ui.unified.FileUploaderParameter(\{ \n| &&
      |                            name: "x-table-name", \n| &&
      |                            value: oInput.getValue().toUpperCase() \n| &&
      |                        \})); \n| &&
      | \n| &&
      |                        let sOp = oGroup.getSelectedIndex() === 1 ? "REPLACE" : "APPEND"; \n| &&
      |                        oFileUploader.addHeaderParameter(new sap.ui.unified.FileUploaderParameter(\{ \n| &&
      |                            name: "x-upload-operation", \n| &&
      |                            value: sOp \n| &&
      |                        \})); \n| &&
      | \n| &&
      |                        oFileUploader.upload() \n| &&
      |                    \}) \n| &&
      |                    let input = new sap.m.Input("tablename") \n| &&
      |                    input.placeAt("layout") \n| &&
      |                    input.setRequired(true) \n| &&
      |                    input.setWidth("600px") \n| &&
      |                    input.setPlaceholder("Target ABAP Table (e.g. ZTABLE)") \n| &&
      |                    line2.placeAt("layout") \n| &&
      |                    line3.placeAt("layout") \n| &&
      |                    line4.placeAt("layout") \n| &&
      |                    let groupDataOptions = new sap.m.RadioButtonGroup("grpDataOptions") \n| &&
      |                    let lblGroupDataOptions = new sap.m.Label("lblDataOptions") \n| &&
      |                    lblGroupDataOptions.setText("Data Upload Options") \n| &&
      |                    lblGroupDataOptions.placeAt("line3") \n| &&
      |                    groupDataOptions.placeAt("line4") \n| &&
      |                    let rbAppend = new sap.m.RadioButton("rbAppend") \n| &&
      |                    let rbReplace = new sap.m.RadioButton("rbReplace") \n| &&
      |                    rbAppend.setText("Append") \n| &&
      |                    rbReplace.setText("Replace") \n| &&
      |                    groupDataOptions.addButton(rbAppend) \n| &&
      |                    groupDataOptions.addButton(rbReplace) \n| &&
      |                    sap.ui.getCore().loadLibrary("sap.ui.unified", \{ \n| &&
      |                        async: true \n| &&
      |                    \}).then(() => \{ \n| &&
      |                        var fileUploader = new sap.ui.unified.FileUploader("fileToUpload") \n| &&
      |                        fileUploader.setFileType(["json"]) \n| &&
      |                        fileUploader.setWidth("400px") \n| &&
      |                        fileUploader.setSendXHR(true) \n| &&
      |                        fileUploader.setUseMultipart(false) \n| && "// Fixes the 400 Bad Request boundary error
      |                        fileUploader.placeAt("line2") \n| &&
      |                        button.placeAt("line2") \n| &&
      |                        fileUploader.attachUploadComplete(function (oEvent) \{ \n| &&
      |                           let sResp = oEvent.getParameter("response") \|\| "Upload Finished"; \n| && "// Fixed unmasked pipe
      |                           MessageBox.information(sResp); \n| && "// Fixed MessageBox reference
      |                        \})   \n| &&
      |                    \}) \n| &&
      |                \}) \n| &&
      |            \}) \n| &&
      |        \}) \n| &&
      |    </script> \n| &&
      |</head> \n| &&
      |<body class="sapUiBody"> \n| &&
      |    <div id="uiArea"></div> \n| &&
      |</body> \n| &&
      |</html> |.
  ENDMETHOD.


  METHOD get_table_primary_keys.
    DATA: lt_dd03l   TYPE TABLE OF dd03l,
          ls_dd03l   TYPE dd03l,
          lv_keyflag TYPE c.

    ev_success = abap_false.
    CLEAR et_keys.

    TRY.
        SELECT * FROM dd03l
          INTO TABLE @lt_dd03l
          WHERE tabname = @iv_tablename
            AND keyflag = 'X'
          ORDER BY position.

        IF sy-subrc = 0 AND lt_dd03l IS NOT INITIAL.
          LOOP AT lt_dd03l INTO ls_dd03l.
            APPEND ls_dd03l-fieldname TO et_keys.
          ENDLOOP.
          ev_success = abap_true.
        ENDIF.

      CATCH cx_root INTO DATA(lx_err).
        CLEAR et_keys.
        ev_success = abap_false.
    ENDTRY.

  ENDMETHOD.


  METHOD perform_update.
    DATA: lv_update_count TYPE i VALUE 0,
          lt_data_local   TYPE REF TO data.

    FIELD-SYMBOLS: <ls_rec>     TYPE any,
                   <lt_tab>     TYPE STANDARD TABLE,
                   <lv_key_val> TYPE any.

    ev_success = abap_false.
    ev_rows_affected = 0.
    CLEAR ev_msg.

    TRY.
        CREATE DATA lt_data_local TYPE (iv_tablename).
        ASSIGN lt_data_local->* TO <ls_rec>.

        LOOP AT it_data ASSIGNING FIELD-SYMBOL(<ls_data>).
          CLEAR <ls_rec>.
          <ls_rec> = <ls_data>.

          UPDATE (iv_tablename) FROM <ls_rec>.

          IF sy-subrc = 0.
            lv_update_count = lv_update_count + sy-dbcnt.
          ELSE.
            ev_msg = 'Update operation failed for a record. Return code: ' && sy-subrc.
            RETURN.
          ENDIF.
        ENDLOOP.

        ev_rows_affected = lv_update_count.
        ev_success = abap_true.
        ev_msg = 'Successfully updated ' && lv_update_count && ' rows.'.

      CATCH cx_root INTO DATA(lx_err).
        ev_success = abap_false.
        ev_msg = 'Error during UPDATE: ' && lx_err->get_text( ).
    ENDTRY.

  ENDMETHOD.


  METHOD perform_upsert.
    DATA: lv_insert_count TYPE i VALUE 0,
          lv_update_count TYPE i VALUE 0,
          lv_total_count  TYPE i VALUE 0,
          lv_key_val_str  TYPE string,
          lt_data_local   TYPE REF TO data,
          lv_exists_count TYPE i.

    FIELD-SYMBOLS: <ls_rec> TYPE any,
                   <ls_key> TYPE any.

    ev_success = abap_false.
    ev_rows_affected = 0.
    CLEAR ev_msg.

    TRY.
        CREATE DATA lt_data_local TYPE TABLE OF (iv_tablename).
        ASSIGN lt_data_local->* TO <ls_rec>.

        LOOP AT it_data ASSIGNING FIELD-SYMBOL(<ls_data>).
          CLEAR <ls_rec>.
          <ls_rec> = <ls_data>.

          "Check if record exists using primary keys
          lv_exists_count = 0.
          LOOP AT it_key_fields INTO DATA(lv_key_field).
            ASSIGN COMPONENT lv_key_field OF STRUCTURE <ls_data> TO <ls_key>.
            IF sy-subrc = 0.
              IF <ls_key> IS ASSIGNED.
                lv_exists_count = lv_exists_count + 1.
              ENDIF.
            ENDIF.
          ENDLOOP.

          IF lv_exists_count > 0.
            "Try UPDATE first
            UPDATE (iv_tablename) FROM <ls_rec>.
            IF sy-subrc = 0 AND sy-dbcnt > 0.
              lv_update_count = lv_update_count + sy-dbcnt.
            ELSE.
              "If UPDATE didn't affect any rows, INSERT instead
              INSERT (iv_tablename) FROM <ls_rec>.
              IF sy-subrc = 0.
                lv_insert_count = lv_insert_count + sy-dbcnt.
              ELSE.
                ev_msg = 'UPSERT failed for a record. Return code: ' && sy-subrc.
                RETURN.
              ENDIF.
            ENDIF.
          ELSE.
            "No key values found, just try INSERT
            INSERT (iv_tablename) FROM <ls_rec>.
            IF sy-subrc = 0.
              lv_insert_count = lv_insert_count + sy-dbcnt.
            ELSE.
              ev_msg = 'Insert operation failed for a record. Return code: ' && sy-subrc.
              RETURN.
            ENDIF.
          ENDIF.
        ENDLOOP.

        lv_total_count = lv_insert_count + lv_update_count.
        ev_rows_affected = lv_total_count.
        ev_success = abap_true.
        ev_msg = 'UPSERT complete. Inserted: ' && lv_insert_count && ', Updated: ' && lv_update_count && ', Total: ' && lv_total_count.

      CATCH cx_root INTO DATA(lx_err).
        ev_success = abap_false.
        ev_msg = 'Error during UPSERT: ' && lx_err->get_text( ).
    ENDTRY.

  ENDMETHOD.


  METHOD validate_table_exists.
    DATA: lt_tabl TYPE TABLE OF dd02l,
          ls_tabl TYPE dd02l.

    ev_exists = abap_false.
    CLEAR ev_error_msg.

    TRY.
        SELECT SINGLE * FROM dd02l
          INTO @ls_tabl
          WHERE tabname = @iv_tablename
            AND tabclass IN ('TRANSP', 'INTTAB', 'APPEND', 'POOL', 'CLUST').

        IF sy-subrc = 0 AND ls_tabl-tabname IS NOT INITIAL.
          ev_exists = abap_true .
        ELSE.
          ev_error_msg = 'Table not found in DD02L or is not a valid data table.'.
        ENDIF.

      CATCH cx_root INTO DATA(lx_err).
        ev_exists = abap_false.
        ev_error_msg = lx_err->get_text( ).
    ENDTRY.

  ENDMETHOD.
ENDCLASS.
