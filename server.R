library(shiny)
library(shinydashboard)
library(googleAuthR)
library(bigQueryR)
library(DT)
library(dygraphs)
library(d3heatmap)
library(listviewer)
library(ggplot2)


shinyServer(function(input, output, session){
  options("googleAuthR.scopes.selected" = getOption("bigQueryR.scope") )
  
  ## The bigQueryR client Ids do not have billing enabled, 
  ## so to work with your own data you need to replace the below with your own
  ## Google API console keys with billing enabled. Do that here:
  ## https://console.developers.google.com/apis/credentials/oauthclient

  options("googleAuthR.webapp.client_id" = getOption("bigQueryR.webapp.client_id"))
  options("googleAuthR.webapp.client_secret" = getOption("bigQueryR.webapp.client_secret"))
  
  ## Once you have made your keys comment out the above options and comment in the below 
#   options("googleAuthR.webapp.client_id" = "YOUR_CLIENT_ID_FOR_OAUTH_TYPE_WEB_APPLICATION")
#   options("googleAuthR.webapp.client_secret" = "YOUR_CLIENT_SECRET_FOR_OAUTH_TYPE_WEB_APPLICATION")
  
  ## Get auth code from return URL
  access_token_oauth  <- reactiveAccessToken(session)
  
  access_token <- reactive({
    if(!is.null(input$json_upload)){
      the_file <- input$json_upload
      
      token <- googleAuthR::gar_auth_service(the_file$datapath)
    } else {
      token <- access_token_oauth()
    }
    
    token
      
  })
  
  ## Make a loginButton to display using loginOutput
  output$loginButton <- renderLogin(session, access_token(),
                                    logout_class = "btn btn-danger")
  
  output$logged_in <- renderText({
    if(!is.null(isolate(access_token()))){
      paste("Logged in:", Sys.time())
    } else {
      "Waiting"
    }
  })
  
  output$fetch_data_button <- renderUI({
    if(is.null(isolate(access_token()))){
      loginOutput("loginButton")
    } else {
      tagList(
        column(6,
          actionButton("do_sql", "Fetch BigQuery Data", icon=icon("cloud-download"))
        ),
        column(6,
               loginOutput("loginButton")
               )
      )
    }
  })
  
  ## upload file - not working yet due to httr bug
  output$uploadJSON <- renderUI({
    
    access_token <- access_token()
    
    if(is.null(isolate(access_token))){
      fileInput("json_upload", "Upload JSON secret", accept="json")
    } else {
      fileInput("json_upload", "Upload again", accept="json")
    }
  })
  
  bq_project <- reactive({
    shiny::validate(
      need(access_token(), "Authenticate to get started.")
    )

    projects <- with_shiny(bqr_list_projects, access_token())
    
    rbind(projects[,c("id","projectId","friendlyName")],
          data.frame(id = "publicdata",
                     projectId = "publicdata",
                     friendlyName = "Public Data"))
    
  })
  
  ## update project_select
  observe({
    shiny::validate(
      need(access_token(), "Authenticate to get started."),
      need(bq_project(), "Select Project")
    )
    projects <- bq_project()
    
    if(!is.null(projects)){
      updateSelectInput(session,
                        "project_select",
                        choices = projects$friendlyName)     
      
    } else {
      updateSelectInput(session,
                        "project_select",
                        choices = NULL) 
    }
  
  
  })
  
  bq_dataset <- reactive({
    shiny::validate(
      need(access_token(), "Authenticate to get started."),
      need(bq_project(), "Select Project")
    )
    
    selected_project <- input$project_select
    projects <- bq_project()
    
    project_id <- projects[projects$friendlyName == selected_project,"projectId"]
    
    with_shiny(bqr_list_datasets, access_token(), project_id)
    
  })
  
  ## update dataset_select
  observe({
    shiny::validate(
      need(access_token(), "Authenticate to get started."),
      need(input$project_select, "Select Project"),
      need(bq_project(), "Select Project")
    )
    datasets <- bq_dataset()
    
    if(!is.null(datasets)){
      updateSelectInput(session,
                        "dataset_select",
                        choices = datasets$id)     
      
    } else {
      updateSelectInput(session,
                        "dataset_select",
                        choices = NULL) 
    }
  })
  
  bq_tables <- reactive({
    shiny::validate(
      need(access_token(), "Authenticate to get started."),
      need(input$dataset_select, "Select Dataset"),
      need(bq_dataset(), "Fetching Datasets"),
      need(bq_project(), "Fetching Projects"),
      need(input$project_select, "Select Project")
    )
    dataset <- input$dataset_select
    datasets <- bq_dataset()

    dataset_id <- datasets[datasets$id == dataset, "datasetId"]
    project_id <- datasets[datasets$id == dataset, "projectId"]
    
    if(all(nrow(dataset_id) > 0, dataset_id == "**No Datasets**")){
      d <- data.frame(id = paste0(project_id,":"),
                      tableId = "No tables in this dataset")
    } else {
      d <- with_shiny(bqr_list_tables, access_token(), 
                      datasetId = dataset_id, projectId = project_id)
    }
    
    d
    
  })
  
  output$bq_tables <- DT::renderDataTable({
    shiny::validate(
      need(access_token(), "Authenticate to get started."),
      need(bq_tables(), "Fetching Tables"),
      need(input$dataset_select, "Select Dataset")
    )
    
    if(!is.null(input$dataset_select)){
      table <- bq_tables()
      
      table[,c("id","tableId")]
    }

    
  }, selection = 'single')
  
  output$table_meta <- renderJsonedit({
    shiny::validate(
      need(access_token(), "Authenticate to get started."),
      need(bq_tables(), "Fetching Tables"),
      need(input$bq_tables_row_last_clicked, "Select Table")
    )
    
    bq_table <- bq_tables()
    selection <- input$bq_tables_row_last_clicked
    
    table_row <- bq_table[selection,]
    
    if(table_row$tableId != "No tables in this dataset"){
      meta_data <- with_shiny(bqr_table_meta,
                              access_token(),
                              projectId = as.character(table_row$projectId),
                              datasetId = as.character(table_row$datasetId),
                              tableId = as.character(table_row$tableId))
      
      listviewer::jsonedit(meta_data)
    }

    
  })
  

  
  bq_data <- eventReactive(input$do_sql, {
    shiny::validate(
      need(access_token(), "Authenticate to get started.")
    )
    sql <- input$bq_sql
    
    dataset <- input$dataset_select
    datasets <- bq_dataset()
    
    if(dataset == "**No Datasets**") {
      dataset_id <- "samples"
    } else {
      dataset_id <- datasets[datasets$id == dataset, "datasetId"]
    }
    
    project_id <- datasets[datasets$id == dataset, "projectId"]

    
    data <- with_shiny(bqr_query, access_token(), 
                       projectId = project_id , datasetId = dataset_id, 
                       query = sql,
                       maxResults = 100000)
    
    if(inherits(data, "bigQueryR_query_error")){
      warning("Error fetching BigQuery SQL")
    }
    
    data
    
  })
  
  output$sql_data <- DT::renderDataTable({
    shiny::validate(
      need(access_token(), "Authenticate to get started."),
      need(bq_data(), "Get BigQuery Data")
    )
    
    bq_data()
    
  })
  
## Example public data query for this graph:
  #     SELECT repository.language, COUNT(repository.url) as freq, COUNT(repository.language) as lang FROM [publicdata:samples.github_nested] 
  #     WHERE repository.language IS NOT Null GROUP BY repository.language ORDER BY freq DESC LIMIT 1000
  output$heatmap <- renderD3heatmap({
    shiny::validate(
      need(access_token(), "Authenticate to get started."),
      need(bq_data(), "Get BigQuery Data"),
      need(!inherits(bq_data(), "bigQueryR_query_error"), "SQL Error")
    )
    
    bq_data <- bq_data()
    scale_c <- input$heat_col
    
    if(any(duplicated(as.character(bq_data[,1])))) return(NULL)
    
    row.names(bq_data) <- as.character(bq_data[,1])

    heat <- bq_data[,-1, drop = FALSE]
    
    if(dim(heat)[2] > 1){
      d <- d3heatmap(heat, scale = scale_c, xaxis_font_size = '8px')
    } else {
      d <- NULL
    }
    
    d

  })
  
  output$ggplot_p <- renderPlot({
    shiny::validate(
      need(access_token(), "Authenticate to get started."),
      need(bq_data(), "Get BigQuery Data"),
      need(!inherits(bq_data(), "bigQueryR_query_error"), "SQL Error"),
      need(input$x_scat, "X-axis choice"),
      need(input$y_scat, "Y-axis choice"),
      need(input$colour_scat, "Colour choice"),
      need(input$size_scat, "Size choice"),
      need(input$plot_type, "Plot choice")
    )
    
    bq_data <- bq_data()
    bq_data <- bq_data[sapply(bq_data, is.numeric)]
    
    x <- input$x_scat
    y <- input$y_scat
    colour <- input$colour_scat
    size <- input$size_scat
    type <- input$plot_type
    
    if(x == "Index") bq_data$Index <- 1:nrow(bq_data)
    if(size == "None") size <- NULL
    if(colour == "None") colour <- NULL
    
    p <- ggplot(bq_data, aes_string(x = x, y = y, colour = colour, size = size )) + theme_bw()
    p <- switch(type,
                scatter = p + geom_point(),
                line = p + geom_line(aes(size = NULL)),
                density =  p + geom_density(aes(y = ..scaled..)),
                area = p + geom_area(aes(colour = NULL, size = NULL), fill = "darkred"),
                bar = p + geom_bar(stat = "identity", aes_string(fill = colour, size = NULL)),
                dotplot = p + geom_dotplot(aes(fill = NULL, colour = NULL), fill = "darkgreen"),
                hexplot = p + geom_hex(aes_string(x = as.factor(x))),
                violin = p + geom_violin(aes(colour = NULL, fill = NULL), fill = "blue")
                )
    
    print(p)
    
  })
  
  observe({
    shiny::validate(
      need(access_token(), "Authenticate to get started."),
      need(bq_data(), "Get BigQuery Data"),
      need(!inherits(bq_data(), "bigQueryR_query_error"), "SQL Error")
    )
    
    bq_data <- bq_data()
    bq_data <- bq_data[sapply(bq_data, is.numeric)]
    
    choice <- names(bq_data)
    choice_i <- c("Index", choice)
    choice_opt <- c("None", choice)
    
    s_2 <- s_3 <- s_4 <- choice[1]
    s_2 <- if(!is.na(choice[2])) choice[2]
    s_3 <- if(!is.na(choice[3])) choice[3]
    s_4 <- if(!is.na(choice[4])) choice[4]
    
    updateSelectInput(session,
                      "hist_choice", "Plot", choices=choice)
    
    updateSelectInput(session, "x_scat", "x-axis", 
                      choices=choice_i)
    
    updateSelectInput(session, "y_scat", "y-axis", 
                      choices=choice, selected = s_2)
    
    updateSelectInput(session, "colour_scat", "Colour", 
                      choices=choice_opt, selected = s_3)
    
    updateSelectInput(session, "size_scat", "Size", 
                      choices=choice_opt, selected = s_4)
  })
  
  observe({
    shiny::validate(
      need(access_token(), "Authenticate to get started."),
      need(bq_data(), "Get BigQuery Data"),
      need(!inherits(bq_data(), "bigQueryR_query_error"), "SQL Error")
    )

    choice <- names(bq_data())
    
    updateSelectInput(session,
                      "hist_choice", "Plot", choices=choice)
  })
  
  observe({
    shiny::validate(
      need(access_token(), "Authenticate to get started."),
      need(bq_data(), "Get BigQuery Data"),
      need(!inherits(bq_data(), "bigQueryR_query_error"), "SQL Error")
    )
    
    bq_data <- bq_data()
    
    bq_numeric <- bq_data[sapply(bq_data, is.numeric)]
    
    if(length(names(bq_numeric)) > 1){
      choice <- c("Index",names(bq_numeric))
    } else {
      choice <- names(bq_numeric)
    }
    
    updateSelectInput(session,
                      "x_line", "X-Axis", choices=choice)
  })
  
})